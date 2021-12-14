#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <chrono>
#include <mutex>

#include "constants.h"
#include "uv.h"
#include "messages.h"
#include "pow.h"
#include "worker.h"
#include "template.h"
#include "fpga_miner.h"

typedef std::chrono::high_resolution_clock Time;
typedef std::chrono::duration<double> duration_t;
typedef std::chrono::time_point<std::chrono::high_resolution_clock> time_point_t;


uv_loop_t *loop;
uv_stream_t *tcp;

time_point_t start_time = Time::now();

std::atomic<uint64_t> total_mining_count;

queue_t G_QUEUE_S;
miner_request_t G_MINER_REQS[parallel_mining_works];

void on_write_end(uv_write_t *req, int status)
{

	//printf("           On write end\n");
    if (status < 0) {
        fprintf(stderr, "error on_write_end");
        exit(1);
    }
    free(req);
    //sprintf("sent new block\n");
}

uint8_t write_buffer[4096 * 1024];
std::mutex write_mutex;
void submit_new_block(mining_worker_t *worker)
{
	assert(load_worker__template(worker) != NULL);
    if (!expire_template_for_new_block(load_worker__template(worker))) {
        printf("mined a parallel block, will not submit\n");
        return;
    }

    job_t *job = load_worker__template(worker)->job;

    if (check_hash(worker->hash, &job->target, job->from_group, job->to_group)){
    	printf("\n TRUE\n");
    } else if(check_index(worker->hash, job->from_group, job->to_group)) {
    	printf("Target false\n");
    } else if(check_target(worker->hash, &job->target)) {
    	printf("Index false\n");
    }
    print_hex("found", worker->hash, 32);
    print_hex("with nonce", worker->nonce, 24);
    printf("with hash count: %d\n", worker->hash_count);
    print_hex("with target", job->target.blob, job->target.len);
    printf("target length %d\n", job->target.len);
    printf("with groups: %d %d\n\n", job->from_group, job->to_group);

    const std::lock_guard<std::mutex> lock(write_mutex);

    ssize_t buf_size = write_new_block(worker,write_buffer);
    uv_buf_t buf = uv_buf_init((char *)write_buffer, buf_size);
    print_hex("new block", (uint8_t *)worker->hash, 32);

    uv_write_t *write_req = (uv_write_t *)malloc(sizeof(uv_write_t));
    uint32_t buf_count = 1;
    uv_write(write_req, tcp, &buf, buf_count, on_write_end);
}


void event_cb(cl_event event, cl_int cmd_status, void *id)
{
	if (getenv("XCL_EMULATION_MODE") != NULL) {
		printf("  kernel finished processing request 0x%x\n", *(int*)id);
	}
    mining_worker_t *worker = &mining_workers[*(int*)id];

    copy_results(&G_MINER_REQS[worker->id]);

    if (load_worker__found_good_hash(worker))
    {
        //store_worker_found_good_hash(worker, true);
        submit_new_block(worker);
    }

//	for(cl_uint i = 0; i < chain_nums; i++) {
//		if(mining_templates[i]==NULL) {
//			printf("NULL TEMPLATE index: %d\n", i);
//		}
//	}
    mining_template_t *template_ptr = load_worker__template(worker);
    job_t *job = template_ptr->job;

    uint32_t chain_index = job->from_group * group_nums + job->to_group;
    mining_counts[chain_index].fetch_sub(mining_steps);
    mining_counts[chain_index].fetch_add(worker->hash_count);
    total_mining_count.fetch_add(worker->hash_count);
    //device_mining_count[worker->device_id].fetch_add(worker->hasher->hash_count);

    //mining_counts[chain_index] -= mining_steps;
    //mining_counts[chain_index] += (uint64_t)worker->hash_count;

    free_template(template_ptr);
    //free_buffers(&G_MINER_REQS[*(int*)id]);

    worker->async.data = worker;
    assert(worker->async.data != NULL);
    uv_async_send(&(worker->async));


}

void start_worker_mining(mining_worker_t *worker)
{

	//G_MINER_REQS[worker->id].TargetIn = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,TARGET_LENGTH * sizeof(cl_uint*));
	//G_MINER_REQS[worker->id].HeaderBlobIn = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,HEADERBLOB_LENGTH * sizeof(cl_uint*));
	//G_MINER_REQS[worker->id].NonceIn = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,NONCE_LENGTH*INST_NUM * sizeof(cl_uint*));
	//G_MINER_REQS[worker->id].NonceOut = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,NONCE_LENGTH * sizeof(cl_uint*));
	//G_MINER_REQS[worker->id].HashCounterOut = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,sizeof(cl_uint*));
	//G_MINER_REQS[worker->id].HashOut = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,TARGET_LENGTH * sizeof(cl_uint*));
    // printf("start mine: %d %d\n", work->job->from_group, work->job->to_group);
    reset_worker(worker);
    //auto fpga_begin = std::chrono::high_resolution_clock::now();

    AlephMinerOperator(G_QUEUE_S,G_KRNLS[worker->id],worker,&G_MINER_REQS[worker->id]);

    //auto fpga_end = std::chrono::high_resolution_clock::now();
}

void mine_with_timer(uv_timer_t *timer);

void mine(mining_worker_t *worker)
{
    time_point_t start = Time::now();

    int32_t to_mine_index = next_chain_to_mine();
    //printf("                               TO MINE INDEX %d\n",to_mine_index);
    if (to_mine_index == -1)
    {
        //printf("waiting for new tasks\n");
        worker->timer.data = worker;
        uv_timer_start(&worker->timer, mine_with_timer, 500, 0);
    } else {
    	mining_counts[to_mine_index].fetch_add(mining_steps);
    	setup_template(worker, load_template(to_mine_index));
    	start_worker_mining(worker);
    }

    duration_t elapsed = Time::now() - start;
    // printf("=== mining time: %fs\n", elapsed.count());
}

void mine_with_req(uv_work_t *req)
{
    mining_worker_t *worker = load_req_worker(req);
    mine(worker);
}

void mine_with_async(uv_async_t *handle)
{
    mining_worker_t *worker = (mining_worker_t *)handle->data;
    mine(worker);
}

void mine_with_timer(uv_timer_t *timer)
{
    mining_worker_t *worker = (mining_worker_t *)timer->data;
    mine(worker);
}

void after_mine(uv_work_t *req, int status)
{
    return;
}



void start_mining()
{
    assert(mining_templates_initialized == true);

    start_time = Time::now();

    for (uint32_t i = 0; i < parallel_mining_works; i++)
    {
    	uv_queue_work(loop, &req[i], mine_with_req, after_mine);
    }
}

void start_mining_if_needed()
{

    if (!mining_templates_initialized)
    {
        bool all_initialized = true;
        for (int i = 0; i < chain_nums; i++)
        {
            if (load_template(i) == NULL)
            {
                all_initialized = false;
                break;
            }
        }
        if (all_initialized)
        {
            mining_templates_initialized = true;
            start_mining();
        }
    }
}


void alloc_buffer(uv_handle_t *handle, size_t suggested_size, uv_buf_t *buf)
{
    buf->base = (char *)malloc(suggested_size);
    buf->len = suggested_size;
}

void log_hashrate(uv_timer_t *timer)
{
    time_point_t current_time = Time::now();
    if (current_time > start_time)
    {
        duration_t eplased = current_time - start_time;
        //printf("total mining count: %.0f MH/s ", total_mining_count.load());
        printf("hashrate: %.0f MH/s ", total_mining_count.load() / eplased.count() / 1000000);
        printf("\n");
    }
}


uint8_t read_buf[2048 * 1024 * chain_nums];
blob_t read_blob = { read_buf, 0 };
server_message_t *decode_buf(const uv_buf_t *buf, ssize_t nread)
{
    if (read_blob.len == 0)
    {
        read_blob.blob = (uint8_t *)buf->base;
        read_blob.len = nread;
        server_message_t *message = decode_server_message(&read_blob);
        if (message)
        {
            // some bytes left
            if (read_blob.len > 0)
            {
                memcpy(read_buf, read_blob.blob, read_blob.len);
                read_blob.blob = read_buf;
            }
            return message;
        }
        else
        { // no bytes consumed
            memcpy(read_buf, buf->base, nread);
            read_blob.blob = read_buf;
            read_blob.len = nread;
            return NULL;
        }
    }
    else
    {
        assert(read_blob.blob == read_buf);
        memcpy(read_buf + read_blob.len, buf->base, nread);
        read_blob.len += nread;
        return decode_server_message(&read_blob);
    }
}

void on_read(uv_stream_t *server, ssize_t nread, const uv_buf_t *buf)
{
    if (nread < 0) {
        fprintf(stderr, "error on_read %ld: might be that the full node is not synced, or miner wallets are not setup\n", nread);
        exit(1);
    }

    if (nread == 0) {
        return;
    }

    server_message_t *message = decode_buf(buf, nread);
    if (!message) {
        return;
    }

    //printf("message type: %d\n", message->kind);
    switch (message->kind)
    {
    case JOBS:
        for (int i = 0; i < message->jobs->len; i ++) {
            update_templates(message->jobs->jobs[i]);
        }
        start_mining_if_needed();
        break;

    case SUBMIT_RESULT:
        printf("submitted: %d -> %d: %d \n", message->submit_result->from_group, message->submit_result->to_group, message->submit_result->status);
        break;
    }

    free(buf->base);
    free_server_message_except_jobs(message);
    // uv_close((uv_handle_t *) server, free_close_cb);
}

void on_connect(uv_connect_t *req, int status)
{
    if (status < 0)
    {
        fprintf(stderr, "connection error %d: might be that the full node is reachable\n", status);
        exit(1);
    }
    printf("the server is connected %d %p\n", status, req);

    tcp = req->handle;
    uv_read_start(req->handle, alloc_buffer, on_read);
}

bool is_valid_ip_address(char *ip_address)
{
    struct sockaddr_in sa;
    int result = inet_pton(AF_INET, ip_address, &(sa.sin_addr));
    return result != 0;
}

int hostname_to_ip(char *ip_address, char *hostname)
{
    struct addrinfo hints, *servinfo;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    int res = getaddrinfo(hostname, NULL, &hints, &servinfo);
    if (res != 0) {
      fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(res));
      return 1;
    }

    struct sockaddr_in *h = (struct sockaddr_in *) servinfo->ai_addr;
    strcpy(ip_address, inet_ntoa(h->sin_addr));

    freeaddrinfo(servinfo);
    return 0;
}

int main(int argc, char **argv)
{
	//fpga setup
    cl_int err;                            // error code returned from api calls

    device_config_t dev_conf;

    //uv_mutex_init(&G_MUTEX);

    if (argc != 2) {
        printf("Usage: %s xclbin\n", argv[0]);
        return EXIT_FAILURE;
    }

    err = configure_board(&dev_conf,argv);

    // Create a dispatcher of requests to the Blur kernel(s)
    G_QUEUE_S = AlephMinerDispatcher(dev_conf);


    //setbuf(stdout, NULL);
	mining_workers_init();

    char broker_ip[16];
    memset(broker_ip, '\0', sizeof(broker_ip));

    if (argc >= 3) {
       if (is_valid_ip_address(argv[2])) {
         strcpy(broker_ip, argv[2]);
       } else {
         hostname_to_ip(broker_ip, argv[2]);
       }
     } else {
       strcpy(broker_ip, "127.0.0.1");
     }

    printf("Will connect to broker @%s:10973\n", broker_ip);


    loop = uv_default_loop();

    uv_tcp_t *socket = (uv_tcp_t *)malloc(sizeof(uv_tcp_t));
    uv_tcp_init(loop, socket);
    uv_connect_t *connect = (uv_connect_t *)malloc(sizeof(uv_connect_t));
    struct sockaddr_in dest;
    uv_ip4_addr(broker_ip, 10973, &dest);
    uv_tcp_connect(connect, socket, (const struct sockaddr *)&dest, on_connect);

    for (int i = 0; i < parallel_mining_works; i++)
    {
    	G_MINER_REQS[i].Data = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,(TARGET_LENGTH+NONCE_LENGTH*INST_NUM+HEADERBLOB_LENGTH) * sizeof(cl_uint*));
    	G_MINER_REQS[i].Results = (cl_uint*)aligned_alloc(MEM_ALIGNMENT,(NONCE_LENGTH+1+TARGET_LENGTH) * sizeof(cl_uint*));
        uv_async_init(loop, &(mining_workers[i].async), mine_with_async);
        uv_timer_init(loop, &(mining_workers[i].timer));
    }

    uv_timer_t log_timer;
    uv_timer_init(loop, &log_timer);
    uv_timer_start(&log_timer, log_hashrate, 5000, 5000);

    uv_run(loop, UV_RUN_DEFAULT);

    return (0);
}


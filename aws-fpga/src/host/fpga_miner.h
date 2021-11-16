/*
 * fpga_miner.h
 *
 *  Created on: Nov 7, 2021
 *      Author: centos
 */

#ifndef SRC_FPGA_MINER_H_
#define SRC_FPGA_MINER_H_

#include <fcntl.h>
#include <stdio.h>
#include <iostream>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#ifdef _WINDOWS
#include <io.h>
#else
#include <unistd.h>
#include <sys/time.h>
#endif
#include <assert.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <CL/opencl.h>
#include <CL/cl_ext.h>
#include "xclhal2.h"
#include "worker.h"
#include "uv.h"
#include <vector>
// This file is required for OpenCL C++ wrapper APIs
//#include "xcl2.hpp"

#define NUM_WORKGROUPS (1)
#define WORKGROUP_SIZE (256)
#define MAX_LENGTH 8192
#define INST_NUM 2
#define NCU 8
#define TARGET_LENGTH 8
#define NONCE_LENGTH 6
#define HEADERBLOB_LENGTH 76
#define HASHCOUNTER_LENGTH 1
#define CHUNK_LENGTH 328
#define NONCE_DIFF 4096
#define MEM_ALIGNMENT 4096
#if defined(VITIS_PLATFORM) && !defined(TARGET_DEVICE)
#define STR_VALUE(arg)      #arg
#define GET_STRING(name) STR_VALUE(name)
#define TARGET_DEVICE GET_STRING(VITIS_PLATFORM)
#endif

uv_mutex_t G_MUTEX;

std::string G_KRNL_NAME = "AlephMiner";
std::vector<cl_kernel> G_KRNLS(NCU);




// -------------------------------------------------------------------------------------------
// Struct returned by BlurDispatcher() and used to keep track of the request sent to the kernel
// The sync() method waits for completion of the request. After it returns, results are ready
// -------------------------------------------------------------------------------------------
typedef struct miner_request_t {
  cl_event mEvent[7];
  int      mId;
  cl_uint* NonceIn;
  cl_uint* TargetIn;
  cl_uint* HeaderBlobIn;
  cl_uint* NonceOut;
  cl_uint* HashCounterOut;
  cl_uint* HashOut;
  cl_mem  mSrc[3];
  cl_mem  mDst[3];
}miner_request_t;

void sync(miner_request_t *miner_req)
{
	printf("INFO: Sync starts #%d\n", miner_req->mId);
	// Wait until the outputs have been read back
	clWaitForEvents(1, &(miner_req->mEvent[2]));
	printf("INFO: Releases events\n");
	clReleaseEvent(miner_req->mEvent[0]);
	clReleaseEvent(miner_req->mEvent[1]);
	clReleaseEvent(miner_req->mEvent[2]);
}


unsigned int conc(uint8_t *bytes) {

    return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];

}

////////////////////////////////////////////////////////////////////////////////

cl_uint load_file_to_memory(const char *filename, char **result)
{
    cl_uint size = 0;
    FILE *f = fopen(filename, "rb");
    if (f == NULL) {
        *result = NULL;
        return -1; // -1 means file opening fail
    }
    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);
    *result = (char *)malloc(size+1);
    if (size != fread(*result, sizeof(char), size, f)) {
        free(*result);
        return -2; // -2 means file reading fail
    }
    fclose(f);
    (*result)[size] = 0;
    return size;
}//load_file_to_memory

void print_results(cl_uint* nonce, cl_uint* hashcounter, cl_uint* hash)
{

	for (cl_uint i = 0; i < NONCE_LENGTH; i++) {
		printf("NONCE - array index %d (host addr 0x%03x) output=0x%x\n", i, i*4,  nonce[i]);
	}

	printf("HASHCOUNTER - output=0x%x\n",  hashcounter[0]);

	for (cl_uint i = 0; i < TARGET_LENGTH; i++) {
		printf("HASH - array index %d (host addr 0x%03x) output=0x%x\n", i, i*4,  hash[i]);
	}

}

void print_miner_worker_results(mining_worker_t* mining_worker)
{

	for (cl_uint i = 0; i < NONCE_LENGTH*4; i++) {
		printf("NONCE - array index %d output=0x%x\n", i,  mining_worker->nonce[i]);
	}

	printf("HASHCOUNTER - output=0x%x\n",  mining_worker->hash_count);

	for (cl_uint i = 0; i < TARGET_LENGTH*4; i++) {
		printf("HASH - array index %d output=0x%x\n", i,  mining_worker->hash[i]);
	}

}

// -------------------------------------------------------------------------------------------
// An event callback function that prints the operations performed by the OpenCL runtime.
// -------------------------------------------------------------------------------------------
void event_cb(cl_event event, cl_int cmd_status, void *id);


void copy_results(miner_request_t* miner_req) {

	printf("Copy results of thread #%d\n",miner_req->mId);

	for(cl_uint i = 0; i < NONCE_LENGTH; i++) {
	    mining_workers[miner_req->mId].nonce[i*4] = (miner_req->NonceOut[NONCE_LENGTH-i-1] >> 24) & 0xFF;
	    mining_workers[miner_req->mId].nonce[i*4+1] = (miner_req->NonceOut[NONCE_LENGTH-i-1] >> 16) & 0xFF;
	    mining_workers[miner_req->mId].nonce[i*4+2] = (miner_req->NonceOut[NONCE_LENGTH-i-1] >> 8) & 0xFF;
	    mining_workers[miner_req->mId].nonce[i*4+3] = miner_req->NonceOut[NONCE_LENGTH-i-1] & 0xFF;
	}

	//sync(request[*(int*)id]);
	//printf("HASHCOUNTER - output=0x%x\n",  G_HASHCOUNTER[*(int*)id]);
	mining_workers[miner_req->mId].hash_count=(uint32_t)miner_req->HashCounterOut[0];
	printf("HASHCOUNTER #%d - output=0x%x\n",miner_req->mId,  mining_workers[miner_req->mId].hash_count);

	for(cl_uint i = 0; i < TARGET_LENGTH; i++) {
	    mining_workers[miner_req->mId].hash[i*4] =   (miner_req->HashOut[TARGET_LENGTH-i-1] >> 24) & 0xFF;
	    mining_workers[miner_req->mId].hash[i*4+1] = (miner_req->HashOut[TARGET_LENGTH-i-1] >> 16) & 0xFF;
	    mining_workers[miner_req->mId].hash[i*4+2] = (miner_req->HashOut[TARGET_LENGTH-i-1] >> 8) & 0xFF;
	    mining_workers[miner_req->mId].hash[i*4+3] =  miner_req->HashOut[TARGET_LENGTH-i-1] & 0xFF;
	}

	for(cl_uint i = 0; i < 3; i++) {
		clReleaseMemObject(miner_req->mSrc[i]);
		clReleaseMemObject(miner_req->mDst[i]);
	}



	store_worker_found_good_hash(&mining_workers[miner_req->mId], true);
}


typedef struct device_config_t {

    cl_device_id     Device;
    cl_context       Context;
  	cl_program       Program;
}device_config_t;

typedef struct queue_t {
	cl_command_queue mQueue;
	cl_context mContext;
	cl_int            mErr;
}kernel_t;


// -------------------------------------------------------------------------------------------
// Class used to dispatch requests to the kernel
// The BlurDispatcher() method schedules the necessary operations (write, kernel, read) and
// returns a BlurRequest* struct which can be used to track the completion of the request.
// The dispatcher has its own OOO command queue allowing multiple requests to be scheduled
// and executed independently by the OpenCL runtime.
// -------------------------------------------------------------------------------------------


queue_t AlephMinerDispatcher(device_config_t dev_conf)
  {
	  cl_int mErr;
	  kernel_t queue_s;
	  std::string cu_id;
	  //cl_queue_properties queue_props = CL_QUEUE_PROFILING_ENABLE | CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE;
	  //kernel_s.mKernel  = clCreateKernel(dev_conf.Program, "AlephMiner", &(kernel_s.mErr));

	  for (int i = 0; i < NCU; i++) {
		  cu_id = std::to_string(i + 1);
	      std::string krnl_name_full = G_KRNL_NAME + ":{" + "AlephMiner_" + cu_id + "}";
	      printf("Creating a kernel [%s] for CU(%d)\n", krnl_name_full.c_str(), i);
	      // Here Kernel object is created by specifying kernel name along with
	      // compute unit.
	      // For such case, this kernel object can only access the specific
	      // Compute unit
	      G_KRNLS[i] = clCreateKernel(dev_conf.Program, krnl_name_full.c_str(), &mErr);
	      if (mErr != CL_SUCCESS) {
	        printf("Return code for clCreateKernel: 0x%x\n",  mErr);
	      }
	  }
	  //kernel_s.mQueue = clCreateCommandQueueWithProperties(dev_conf.Context, dev_conf.Device, &queue_props, &mErr);
	  queue_s.mQueue   = clCreateCommandQueue(dev_conf.Context, dev_conf.Device, CL_QUEUE_PROFILING_ENABLE | CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE, &mErr);
	  queue_s.mContext = dev_conf.Context;
	  return queue_s;
  }

void AlephMinerOperator(
	  	queue_t queue_s,
		cl_kernel mKernel,
	    mining_worker_t *work,
		miner_request_t *miner_req
		)
	  {


		cl_mem_ext_ptr_t  mSrcExt[3];
		cl_mem_ext_ptr_t  mDstExt[3];
		cl_mem            mSrc[3];
		cl_mem            mDst[3];
		cl_int            mErr;

		size_t global = 1;
		size_t local = 1;

	  	 //= new AlephMinerRequest(mCounter++);
		miner_req->mId = work->id;

		printf(" Start operator of thread #%d\n",miner_req->mId);

	  	int membank = 0;//(mCounter%2);

			job_t *job = load_worker__template(work)->job;
			blob_t *header = &job->header_blob;

			unsigned char FromGroup = job->from_group;
			unsigned char ToGroup = job->to_group;
			unsigned char Groups = group_nums;
			unsigned char GroupsShifter = (Groups/2);
			unsigned char ChainNum = chain_nums;
			unsigned short ChunkLength = CHUNK_LENGTH;

			uint8_t data_var[4];


			//req->HeaderBlobIn = &(unsigned int)header->blob;

			// copying wih changing the order
			for(cl_uint i = 0; i < TARGET_LENGTH; i++) {
				for(cl_uint j = 0; j < 4; j++) {
					data_var[j] = job->target.blob[28-(i*4)+j];
				}
				miner_req->TargetIn[i] = conc(data_var);
				//printf("TARGETIN - array index %d output=0x%x\n", i,  miner_req->TargetIn[i]);
			}

			// copying wih changing the order
			for(cl_uint i = 0; i < NONCE_LENGTH; i++) {
				for(cl_uint j = 0; j < 4; j++) {
					data_var[j] = work->nonce[20-(i*4)+j];
				}
				for(cl_uint k = 0; k < INST_NUM; k++) {
					if(i==0){
						miner_req->NonceIn[k*NONCE_LENGTH+i] = conc(data_var)+ (NONCE_DIFF*k);
					} else {
						miner_req->NonceIn[k*NONCE_LENGTH+i] = conc(data_var);
					}
					//printf("NONCEIN - array index %d output=0x%x\n", k*NONCE_LENGTH+i,  miner_req->NonceIn[k*NONCE_LENGTH+i]);
				}
				//printf("NONCEIN - array index %d output=0x%x\n", i,  miner_req->NonceIn[i]);
			}


			printf("HEADERBLOB size %d\n", header->len);
			for(cl_uint i = 0; i < HEADERBLOB_LENGTH; i++) {
				miner_req->HeaderBlobIn[i] = 0;
				for(cl_uint j = 0; j < 4; j++) {
					if(i==(HEADERBLOB_LENGTH-1) && j >1) {
						miner_req->HeaderBlobIn[i] |= 0 << ((j)*8);
					} else {
						miner_req->HeaderBlobIn[i] |= (cl_uint)header->blob[i*4+j] << ((j)*8);
					}
				}
				//printf("HEADERBLOBIN - array index %d output=0x%x\n", i,  miner_req->HeaderBlobIn[i]);
			}


    // Create input buffers for Target difficulty (host to device)
	//mSrcExt[0].flags = membank | XCL_MEM_TOPOLOGY;
	//mSrcExt[0].param = 0;
	//mSrcExt[0].obj   = miner_req->TargetIn;
	miner_req->mSrc[0] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  sizeof(unsigned int) * TARGET_LENGTH, miner_req->TargetIn, &mErr);
	//G_TARGET[miner_req->mId] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  sizeof(unsigned int) * TARGET_LENGTH, miner_req->TargetIn, &mErr);
    if (mErr != CL_SUCCESS) {
      printf("Return code for clCreateBuffer on mTargetIn: 0x%x\n",  mErr);
    }

    // Create input buffers for Headerblob (host to device)
	//mSrcExt[1].flags = membank | XCL_MEM_TOPOLOGY;
	//mSrcExt[1].param = 0;
	//mSrcExt[1].obj   = miner_req->HeaderBlobIn;
    miner_req->mSrc[1] = clCreateBuffer(queue_s.mContext,   CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  sizeof(unsigned int) * HEADERBLOB_LENGTH, miner_req->HeaderBlobIn, &mErr);
    //G_HEADERBLOB[miner_req->mId] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  sizeof(unsigned int) * HEADERBLOB_LENGTH, miner_req->HeaderBlobIn, &mErr);
    if (mErr != CL_SUCCESS) {
    	printf("Return code for clCreateBuffer on mHeaderBlobIn: 0x%x\n",  mErr);
    }

    // Create input/output buffers for Nonce
	//mSrcExt[2].flags = membank | XCL_MEM_TOPOLOGY;
	//mSrcExt[2].param = 0;
	//mSrcExt[2].obj   = miner_req->NonceIn;
    miner_req->mSrc[2] = clCreateBuffer(queue_s.mContext,   CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY, (sizeof(unsigned int) * NONCE_LENGTH * INST_NUM), miner_req->NonceIn, &mErr);
    //G_NONCEIN[miner_req->mId] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  (sizeof(unsigned int) * NONCE_LENGTH * INST_NUM), miner_req->NonceIn, &mErr);
    if (mErr != CL_SUCCESS) {
    	printf("Return code for clCreateBuffer on NonceIn: 0x%x\n",  mErr);
    }

    //printf("mDst of thread #%d\n",miner_req->mId);

    // Create output buffer for HashCounter (device to host)
	//mDstExt[0].flags = membank| XCL_MEM_TOPOLOGY;
	//mDstExt[0].param = 0;
	//mDstExt[0].obj   = miner_req->NonceOut;
    miner_req->mDst[0] = clCreateBuffer(queue_s.mContext,   CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint) * NONCE_LENGTH, miner_req->NonceOut, &mErr);
    //G_NONCEOUT[miner_req->mId]  = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint) * NONCE_LENGTH, miner_req->NonceOut, &mErr);
    if (mErr != CL_SUCCESS) {
    	printf("Return code for clCreateBuffer on NonceOut: 0x%x\n",  mErr);
    }


    // Create output buffer for Hash (device to host)
	//mDstExt[1].flags = membank | XCL_MEM_TOPOLOGY;
	//mDstExt[1].param = 0;
	//mDstExt[1].obj   = miner_req->HashCounterOut;//G_HASHCOUNTER[(req->mId)];
    miner_req->mDst[1] = clCreateBuffer(queue_s.mContext,  CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint), miner_req->HashCounterOut, &mErr);
    //G_HASHCOUNTER[miner_req->mId] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint), miner_req->HashCounterOut, &mErr);
    if (mErr != CL_SUCCESS) {
    	printf("Return code for clCreateBuffer on mHashCounterOut: 0x%x\n",  mErr);
    }

    // Create output buffer for Hash (device to host)
	//mDstExt[2].flags = membank | XCL_MEM_TOPOLOGY;
	//mDstExt[2].param = 0;
	//mDstExt[2].obj   = miner_req->HashOut;
    miner_req->mDst[2] = clCreateBuffer(queue_s.mContext,  CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint) * TARGET_LENGTH, miner_req->HashOut, &mErr);
    //G_HASH[miner_req->mId] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint) * TARGET_LENGTH, miner_req->HashOut, &mErr);
    if (mErr != CL_SUCCESS) {
    	printf("Return code for clCreateBuffer on mHashOut: 0x%x\n",  mErr);
    }



  //if (!(mSrc&&mDst)) {
  //    printf("ERROR: Failed to allocate device memory!\n");
  //    printf("ERROR: Test failed\n");
  //}


    printf("Set the arguments of thread #%d\n",miner_req->mId);

    // Set the arguments to our compute kernel
    mErr = 0;
    mErr |= clSetKernelArg(mKernel, 0, sizeof(unsigned char), &FromGroup);
    mErr |= clSetKernelArg(mKernel, 1, sizeof(unsigned char), &ToGroup);
    mErr |= clSetKernelArg(mKernel, 2, sizeof(unsigned char), &Groups);
    mErr |= clSetKernelArg(mKernel, 3, sizeof(unsigned char), &GroupsShifter);
    mErr |= clSetKernelArg(mKernel, 4, sizeof(unsigned char), &ChainNum);
    mErr |= clSetKernelArg(mKernel, 5, sizeof(unsigned short), &ChunkLength);
    mErr |= clSetKernelArg(mKernel, 6, sizeof(cl_mem),  &miner_req->mSrc[0]);
    mErr |= clSetKernelArg(mKernel, 7, sizeof(cl_mem),  &miner_req->mSrc[1]);
    mErr |= clSetKernelArg(mKernel, 8, sizeof(cl_mem),  &miner_req->mSrc[2]);
    mErr |= clSetKernelArg(mKernel, 9, sizeof(cl_mem),  &miner_req->mDst[0]);
    mErr |= clSetKernelArg(mKernel, 10, sizeof(cl_mem), &miner_req->mDst[1]);
    mErr |= clSetKernelArg(mKernel, 11, sizeof(cl_mem), &miner_req->mDst[2]);
    //mErr |= clSetKernelArg(mKernel, 6, sizeof(cl_mem), &G_TARGET[miner_req->mId]);
    //mErr |= clSetKernelArg(mKernel, 7, sizeof(cl_mem), &G_HEADERBLOB[miner_req->mId]);
    //mErr |= clSetKernelArg(mKernel, 8, sizeof(cl_mem), &G_NONCEIN[miner_req->mId]);
    //mErr |= clSetKernelArg(mKernel, 9, sizeof(cl_mem), &G_NONCEOUT[miner_req->mId]);
    //mErr |= clSetKernelArg(mKernel, 10, sizeof(cl_mem), &G_HASHCOUNTER[miner_req->mId]);
    //mErr |= clSetKernelArg(mKernel, 11, sizeof(cl_mem), &G_HASH[miner_req->mId]);

    if (mErr != CL_SUCCESS) {
        printf("ERROR: Failed to set kernel arguments! %d\n", mErr);
        printf("ERROR: Test failed\n");
    }

    //uv_mutex_lock(&G_MUTEX);

	// Schedule the writing of the inputs
	mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 3,miner_req->mSrc, 0, 0, nullptr,  &miner_req->mEvent[0]);


	if (mErr != CL_SUCCESS) {
      printf("ERROR: Failed to write to target source array: %d!\n", mErr);
      printf("ERROR: Test failed\n");
    }

	//// Schedule the writing of the inputs
	//mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1,(cl_mem*)G_TARGET[miner_req->mId], 0, 0, nullptr,  &miner_req->mEvent[0]);
    //
    //
	//if (mErr != CL_SUCCESS) {
    //  printf("ERROR: Failed to write to target source array: %d!\n", mErr);
    //  printf("ERROR: Test failed\n");
    //}
	//printf("Migration target\n");
    //
	//mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1,(cl_mem*)G_HEADERBLOB[miner_req->mId], 0, 0, &miner_req->mEvent[0],  &miner_req->mEvent[1]);
    //
    //
	//if (mErr != CL_SUCCESS) {
    //  printf("ERROR: Failed to write to headerblob source array: %d!\n", mErr);
    //  printf("ERROR: Test failed\n");
    //}
    //
	//printf("Migration headerblob target\n");
    //
	//mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1,(cl_mem*)G_NONCEIN[miner_req->mId], 0, 0, &miner_req->mEvent[1],  &miner_req->mEvent[2]);
    //
    //
	//if (mErr != CL_SUCCESS) {
    //  printf("ERROR: Failed to write to noncein source array: %d!\n", mErr);
    //  printf("ERROR: Test failed\n");
    //}
    //
	//printf("Enqueue\n");

		// Schedule the execution of the kernel
		//mErr = clEnqueueTask(kernel_s.mQueue, kernel_s.mKernel, 1,  &miner_req->mEvent[0], &miner_req->mEvent[1]);
		mErr = clEnqueueNDRangeKernel (queue_s.mQueue,mKernel,1,NULL,&global,&local,1, &miner_req->mEvent[0], &miner_req->mEvent[1]);


		if (mErr) {
		printf("ERROR: Failed to execute kernel! %d\n", mErr);
		printf("ERROR: Test failed\n");
	}

	mErr = 0;

	//	// Schedule the reading of the outputs
	//mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1, (cl_mem*)G_NONCEOUT[miner_req->mId], CL_MIGRATE_MEM_OBJECT_HOST, 1, &miner_req->mEvent[3], &miner_req->mEvent[4]);
	////uv_mutex_unlock(&G_MUTEX);
    //
	//if (mErr != CL_SUCCESS) {
	//	printf("ERROR: Failed to read output array! %d\n", mErr);
	//	printf("ERROR: Test failed\n");
	//}
    //
	//// Schedule the reading of the outputs
	//mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1, (cl_mem*)G_HASHCOUNTER[miner_req->mId], CL_MIGRATE_MEM_OBJECT_HOST, 1, &miner_req->mEvent[4], &miner_req->mEvent[5]);
	////uv_mutex_unlock(&G_MUTEX);
    //
	//if (mErr != CL_SUCCESS) {
	//	printf("ERROR: Failed to read output array! %d\n", mErr);
	//	printf("ERROR: Test failed\n");
	//}
    //
	//// Schedule the reading of the outputs
	//mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1, (cl_mem*)G_HASH[miner_req->mId], CL_MIGRATE_MEM_OBJECT_HOST, 1, &miner_req->mEvent[5], &miner_req->mEvent[6]);
	//uv_mutex_unlock(&G_MUTEX);

	mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 3, miner_req->mDst, CL_MIGRATE_MEM_OBJECT_HOST, 1, &miner_req->mEvent[1], &miner_req->mEvent[2]);

	if (mErr != CL_SUCCESS) {
	printf("ERROR: Failed to read output array! %d\n", mErr);
	printf("ERROR: Test failed\n");
}

	// Register call back to notify of kernel completion
	clSetEventCallback(miner_req->mEvent[2], CL_COMPLETE, event_cb, &miner_req->mId);

	printf("End operator of thread #%d\n",miner_req->mId);



	//return req;
  }

void AlephMinerReleaser(queue_t queue_s)
  {
	clReleaseCommandQueue(queue_s.mQueue);
	for (int i = 0; i < NCU; i++) {
		clReleaseKernel(G_KRNLS[i]);
	}
  }




void free_buffers(cl_uint* target, cl_uint* headerblob, cl_uint* noncein, cl_uint* nonceout, cl_uint* hashcounter, cl_uint* hash)
{
	free(target);
    free(headerblob);
    free(noncein);
    free(nonceout);
    free(hashcounter);
    free(hash);
}

int configure_board(device_config_t *dev_conf,  char** argv)
{
	cl_int err;                            // error code returned from api calls
	cl_platform_id platform_id;         // platform id
    char cl_platform_vendor[1001];
    char target_device_name[1001] = TARGET_DEVICE;
   // Get all platforms and then select Xilinx platform
    cl_platform_id platforms[16];       // platform id
    cl_uint platform_count;
    cl_uint platform_found = 0;
    err = clGetPlatformIDs(16, platforms, &platform_count);
    if (err != CL_SUCCESS) {
        printf("ERROR: Failed to find an OpenCL platform!\n");
        printf("ERROR: Test failed\n");
        return EXIT_FAILURE;
    }
    printf("INFO: Found %d platforms\n", platform_count);

    // Find Xilinx Plaftorm
    for (cl_uint iplat=0; iplat<platform_count; iplat++) {
        err = clGetPlatformInfo(platforms[iplat], CL_PLATFORM_VENDOR, 1000, (void *)cl_platform_vendor,NULL);
        if (err != CL_SUCCESS) {
            printf("ERROR: clGetPlatformInfo(CL_PLATFORM_VENDOR) failed!\n");
            printf("ERROR: Test failed\n");
            return EXIT_FAILURE;
        }
        if (strcmp(cl_platform_vendor, "Xilinx") == 0) {
            printf("INFO: Selected platform %d from %s\n", iplat, cl_platform_vendor);
            platform_id = platforms[iplat];
            platform_found = 1;
        }
    }
    if (!platform_found) {
        printf("ERROR: Platform Xilinx not found. Exit.\n");
        return EXIT_FAILURE;
    }

    // Get Accelerator compute device
    cl_uint num_devices;
    cl_uint device_found = 0;
    cl_device_id devices[16];  // compute device id
    char cl_device_name[1001];
    err = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_ACCELERATOR, 16, devices, &num_devices);
    printf("INFO: Found %d devices\n", num_devices);
    if (err != CL_SUCCESS) {
        printf("ERROR: Failed to create a device group!\n");
        printf("ERROR: Test failed\n");
        return -1;
    }

    //iterate all devices to select the target device.
    for (cl_uint i=0; i<num_devices; i++) {
        err = clGetDeviceInfo(devices[i], CL_DEVICE_NAME, 1024, cl_device_name, 0);
        if (err != CL_SUCCESS) {
            printf("ERROR: Failed to get device name for device %d!\n", i);
            printf("ERROR: Test failed\n");
            return EXIT_FAILURE;
        }
        printf("CL_DEVICE_NAME %s\n", cl_device_name);
        if(strcmp(cl_device_name, target_device_name) == 0) {
            dev_conf->Device = devices[i];
            device_found = 1;
            printf("Selected %s as the target device\n", cl_device_name);
        }
    }

    if (!device_found) {
        printf("ERROR:Target device %s not found. Exit.\n", target_device_name);
        return EXIT_FAILURE;
    }

    // Create a compute context
    //
    dev_conf->Context = clCreateContext(0, 1, &dev_conf->Device, NULL, NULL, &err);
    if (!dev_conf->Context) {
        printf("ERROR: Failed to create a compute context!\n");
        printf("ERROR: Test failed\n");
        return EXIT_FAILURE;
    }


    cl_int status;

    // Create Program Objects
    // Load binary from disk
    unsigned char *kernelbinary;
    char *xclbin = argv[1];

    //------------------------------------------------------------------------------
    // xclbin
    //------------------------------------------------------------------------------
    printf("INFO: loading xclbin %s\n", xclbin);
    cl_uint n_i0 = load_file_to_memory(xclbin, (char **) &kernelbinary);
    if (n_i0 < 0) {
        printf("ERROR: failed to load kernel from xclbin: %s\n", xclbin);
        printf("ERROR: Test failed\n");
        return EXIT_FAILURE;
    }

    size_t n0 = n_i0;

    // Create the compute program from offline
    dev_conf->Program = clCreateProgramWithBinary(dev_conf->Context, 1, &dev_conf->Device, &n0,
                                        (const unsigned char **) &kernelbinary, &status, &err);
    free(kernelbinary);

    if ((!dev_conf->Program) || (err!=CL_SUCCESS)) {
        printf("ERROR: Failed to create compute program from binary %d!\n", err);
        printf("ERROR: Test failed\n");
        return EXIT_FAILURE;
    }


    // Build the program executable
    //
    err = clBuildProgram(dev_conf->Program, 0, NULL, NULL, NULL, NULL);
    if (err != CL_SUCCESS) {
        size_t len;
        char buffer[2048];

        printf("ERROR: Failed to build program executable!\n");
        clGetProgramBuildInfo(dev_conf->Program, dev_conf->Device, CL_PROGRAM_BUILD_LOG, sizeof(buffer), buffer, &len);
        printf("%s\n", buffer);
        printf("ERROR: Test failed\n");
        return EXIT_FAILURE;
    }

    printf("INFO: Build the program executable\n");

    return err;
}

void free_buffers(miner_request_t* miner_req)
{
	free(miner_req->NonceIn      );
    free(miner_req->TargetIn    );
    free(miner_req->HeaderBlobIn );
    free(miner_req->NonceOut    );
    free(miner_req->HashCounterOut);
    free(miner_req->HashOut     );
}

#endif /* SRC_FPGA_MINER_H_ */

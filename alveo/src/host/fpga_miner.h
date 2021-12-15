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
#include "constants.h"
#include <vector>
// This file is required for OpenCL C++ wrapper APIs
//#include "xcl2.hpp"

#define NUM_WORKGROUPS (1)
#define WORKGROUP_SIZE (256)
#define MAX_LENGTH 8192
#define INST_NUM 2
#define NCU parallel_mining_works
#define TARGET_LENGTH 8
#define NONCE_LENGTH 6
#define HEADERBLOB_LENGTH 76
#define HASHCOUNTER_LENGTH 1
#define CHUNK_LENGTH 326
#define NONCE_DIFF mining_steps
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
  cl_event mEvent[3];
  int      mId;
  cl_uint* Data;
  cl_uint* Results;
  cl_mem  mSrc[1];
  cl_mem  mDst[1];
}miner_request_t;

void sync(miner_request_t *miner_req)
{
	printf("INFO: Sync starts #%d\n", miner_req->mId);
	// Wait until the outputs have been read back
	clWaitForEvents(1, &(miner_req->mEvent[2]));
	printf("INFO: Releases events\n");
//	clReleaseEvent(miner_req->mEvent[0]);
//	clReleaseEvent(miner_req->mEvent[1]);
//	clReleaseEvent(miner_req->mEvent[2]);
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

	unsigned int mId = miner_req->mId;
	//printf("#%d thread has finished\n", miner_req->mId);

	for(cl_uint i = 0; i < (NONCE_LENGTH+1+TARGET_LENGTH); i++) {
		if(i<NONCE_LENGTH) {
			mining_workers[mId].nonce[i*4] = (miner_req->Results[i] >> 24) & 0xFF;
			mining_workers[mId].nonce[i*4+1] = (miner_req->Results[i] >> 16) & 0xFF;
			mining_workers[mId].nonce[i*4+2] = (miner_req->Results[i] >> 8) & 0xFF;
			mining_workers[mId].nonce[i*4+3] = miner_req->Results[i] & 0xFF;
			//printf("Nonce - array index %d output=0x%x\n", i,  miner_req->Results[i]);
		} else if(i==NONCE_LENGTH) {
			//memcpy(mining_workers[miner_req->mId].hash_count, *(uint32_t)(miner_req->Results[i]),1);
			mining_workers[mId].hash_count=(uint32_t)(miner_req->Results[i]);
			//printf("Hashcounter - output=0x%x\n",  mining_workers[miner_req->mId].hash_count);
			//printf("Hashcounter - array index %d output=0x%x\n", i,  miner_req->Results[i]);
		} else {
			mining_workers[mId].hash[(i-(NONCE_LENGTH+1))*4] =   (miner_req->Results[i] >> 24) & 0xFF;
			mining_workers[mId].hash[(i-(NONCE_LENGTH+1))*4+1] = (miner_req->Results[i] >> 16) & 0xFF;
			mining_workers[mId].hash[(i-(NONCE_LENGTH+1))*4+2] = (miner_req->Results[i] >> 8) & 0xFF;
			mining_workers[mId].hash[(i-(NONCE_LENGTH+1))*4+3] =  miner_req->Results[i] & 0xFF;
			//printf("Hash - array index %d output=0x%x\n", i,  miner_req->Results[i]);
		}
	}
	//printf("Hashcounter 0x%x\n",mining_workers[mId].hash_count);

	//print_miner_worker_results(&mining_workers[mId]);

	clReleaseMemObject(miner_req->mSrc[0]);
	clReleaseMemObject(miner_req->mDst[0]);

	for(cl_uint i = 0; i < 3; i++) {
		clReleaseEvent(miner_req->mEvent[i]);
	}

	//printf("Hashcounter 0x%x\n",mining_workers[mId].hash_count);
	//checking the invalid bit
	if((mining_workers[mId].hash_count & 0x80000000)==0) {
		store_worker_found_good_hash(&mining_workers[mId], true);
		//printf("Hashcounter - valid 0x%x\n",mining_workers[miner_req->mId].hash_count);
	} else {
		//removing the invalid bit from the hash count value
		mining_workers[mId].hash_count = (mining_workers[mId].hash_count & 0x7FFFFFFF);
		//printf("Hashcounter - invalid 0x%x\n",mining_workers[mId].hash_count);
	}

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

	  	int membank = 0;//(mCounter%2);

			job_t *job = load_worker__template(work)->job;
			blob_t *header = &job->header_blob;

			unsigned char FromGroup = job->from_group;
			unsigned char ToGroup = job->to_group;
			unsigned char Groups = (unsigned char)group_nums;
			unsigned char GroupsShifter = (Groups/2);
			unsigned char ChainNum = (unsigned char)chain_nums;
			unsigned short ChunkLength = (unsigned short)CHUNK_LENGTH;
			unsigned int MiningSteps = (unsigned int)mining_steps;

			int8_t target_idx = (TARGET_LENGTH*4);
			unsigned int headerblob_idx = 0;
			int8_t nonce_idx = 0;

			//printf("AlephMinerOperator %d, mining steps %d\n", miner_req->mId,MiningSteps);

			for(cl_uint i = 0; i < (TARGET_LENGTH + INST_NUM * NONCE_LENGTH + HEADERBLOB_LENGTH); i++) {
				//TargetIn
				if(i < TARGET_LENGTH) {
					for(cl_uint j = 0; j < 4; j++) {
						miner_req->Data[i] = miner_req->Data[i] << 8;
						if(target_idx > job->target.len) {
							miner_req->Data[i] |= 0;
						} else {
							miner_req->Data[i] |= job->target.blob[(job->target.len)-target_idx];
						}
						target_idx--;
					}
					//printf("TARGETIN - array index %d output=0x%x\n", i,  miner_req->Data[i]);
				//NonceIn
				} else if(i < (TARGET_LENGTH + INST_NUM * NONCE_LENGTH)) {
					if(nonce_idx==NONCE_LENGTH) {
						nonce_idx = 0;
					}
					for(cl_uint j = 0; j < 4; j++) {
						miner_req->Data[i] = miner_req->Data[i] << 8;
						miner_req->Data[i] |= work->nonce[nonce_idx*4+j];
					}
					if(i==((TARGET_LENGTH + INST_NUM * NONCE_LENGTH)-1)) {
						miner_req->Data[i] += NONCE_DIFF;
					}
					nonce_idx++;
					//printf("NONCEIN - array index %d output=0x%x\n", i,  miner_req->Data[i]);
				//HeaderBlobIn
				} else {
					headerblob_idx = i - (TARGET_LENGTH + INST_NUM * NONCE_LENGTH);
					miner_req->Data[i] = 0;
					for(cl_uint j = 0; j < 4; j++) {
						if(i==((TARGET_LENGTH + INST_NUM * NONCE_LENGTH + HEADERBLOB_LENGTH)-1) && j >1) {
							miner_req->Data[i] |= 0 << ((j)*8);
						} else {
							miner_req->Data[i] |= (cl_uint)header->blob[headerblob_idx*4+j] << ((j)*8);
						}
					}
					//printf("HEADERBLOBIN - array index %d output=0x%x\n", i,  miner_req->Data[i]);
				}
			}


    // Create input buffers for Target difficulty (host to device)
	//mSrcExt[0].flags = membank | XCL_MEM_TOPOLOGY;
	//mSrcExt[0].param = 0;
	//mSrcExt[0].obj   = miner_req->TargetIn;
	miner_req->mSrc[0] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  sizeof(unsigned int) * (TARGET_LENGTH + NONCE_LENGTH * INST_NUM + HEADERBLOB_LENGTH), miner_req->Data, &mErr);
	//G_TARGET[miner_req->mId] = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY,  sizeof(unsigned int) * TARGET_LENGTH, miner_req->TargetIn, &mErr);
    if (mErr != CL_SUCCESS) {
      printf("Return code for clCreateBuffer on mTargetIn: 0x%x\n",  mErr);
    }


    //printf("mDst of thread #%d\n",miner_req->mId);

    // Create output buffer for HashCounter (device to host)
	//mDstExt[0].flags = membank| XCL_MEM_TOPOLOGY;
	//mDstExt[0].param = 0;
	//mDstExt[0].obj   = miner_req->NonceOut;
    miner_req->mDst[0] = clCreateBuffer(queue_s.mContext,   CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint) * (NONCE_LENGTH+1+TARGET_LENGTH), miner_req->Results, &mErr);
    //G_NONCEOUT[miner_req->mId]  = clCreateBuffer(queue_s.mContext, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY,  sizeof(cl_uint) * NONCE_LENGTH, miner_req->NonceOut, &mErr);
    if (mErr != CL_SUCCESS) {
    	printf("Return code for clCreateBuffer on Results: 0x%x\n",  mErr);
    }




  //if (!(mSrc&&mDst)) {
  //    printf("ERROR: Failed to allocate device memory!\n");
  //    printf("ERROR: Test failed\n");
  //}


    //printf("Set the arguments of thread #%d\n",miner_req->mId);

    // Set the arguments to our compute kernel
    mErr = 0;
    mErr |= clSetKernelArg(mKernel, 0, sizeof(unsigned char), &FromGroup);
    mErr |= clSetKernelArg(mKernel, 1, sizeof(unsigned char), &ToGroup);
    mErr |= clSetKernelArg(mKernel, 2, sizeof(unsigned char), &Groups);
    mErr |= clSetKernelArg(mKernel, 3, sizeof(unsigned char), &GroupsShifter);
    mErr |= clSetKernelArg(mKernel, 4, sizeof(unsigned char), &ChainNum);
    mErr |= clSetKernelArg(mKernel, 5, sizeof(unsigned short), &ChunkLength);
    mErr |= clSetKernelArg(mKernel, 6, sizeof(unsigned int), &MiningSteps);
    mErr |= clSetKernelArg(mKernel, 7, sizeof(cl_mem),  &miner_req->mSrc[0]);
    mErr |= clSetKernelArg(mKernel, 8, sizeof(cl_mem),  &miner_req->mDst[0]);

    //printf("End the arguments of thread #%d\n",miner_req->mId);



    if (mErr != CL_SUCCESS) {
        printf("ERROR: Failed to set kernel arguments! %d\n", mErr);
        printf("ERROR: Test failed\n");
    }

    //uv_mutex_lock(&G_MUTEX);

	// Schedule the writing of the inputs
	mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1, miner_req->mSrc, 0, 0, nullptr,  &miner_req->mEvent[0]);

	//printf("MigrateMemObjects inputs #%d\n",miner_req->mId);

	if (mErr != CL_SUCCESS) {
      printf("ERROR: Failed to write to target source array: %d!\n", mErr);
      printf("ERROR: Test failed\n");
    }



		// Schedule the execution of the kernel
		//mErr = clEnqueueTask(kernel_s.mQueue, kernel_s.mKernel, 1,  &miner_req->mEvent[0], &miner_req->mEvent[1]);
		mErr = clEnqueueNDRangeKernel (queue_s.mQueue,mKernel,1,NULL,&global,&local,1, &miner_req->mEvent[0], &miner_req->mEvent[1]);


		if (mErr) {
		printf("ERROR: Failed to execute kernel! %d\n", mErr);
		printf("ERROR: Test failed\n");
	}

	mErr = 0;

	//printf("MigrateMemObjects output #%d\n",miner_req->mId);


	mErr |= clEnqueueMigrateMemObjects(queue_s.mQueue, 1, miner_req->mDst, CL_MIGRATE_MEM_OBJECT_HOST, 1, &miner_req->mEvent[1], &miner_req->mEvent[2]);

	if (mErr != CL_SUCCESS) {
	printf("ERROR: Failed to read output array! %d\n", mErr);
	printf("ERROR: Test failed\n");
	}

	// Register call back to notify of kernel completion
	clSetEventCallback(miner_req->mEvent[2], CL_COMPLETE, event_cb, &miner_req->mId);

	//printf("end of operator\n");

	//return req;
  }

void AlephMinerReleaser(queue_t queue_s)
  {
	clReleaseCommandQueue(queue_s.mQueue);
	for (int i = 0; i < NCU; i++) {
		clReleaseKernel(G_KRNLS[i]);
	}
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
	free(miner_req->Data      );
    free(miner_req->Results    );

}

#endif /* SRC_FPGA_MINER_H_ */

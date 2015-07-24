#include "MyCuda.h"

/**
* ÿ�� warp �Զ�ͬ�������� __syncthreads();
* volatile : ���Ϲؼ���volatile�ı�����������Ϊ���б�������˼�Ǽ���volatile
*            �ı������ڴ��е�ֵ���ܻ���ʱ�����仯��������Ҫȥ��ȡ�������ʱ��
             ����Ҫ���ڴ��ж�ȡ�������Ǵӻ����ж�ȡ
* sdata  ����ͷָ�룬����λ�ڹ����ڴ�
* tid    �߳�����
*/
__device__ void warpReduce(volatile float *sdata, int tid)
{
	sdata[tid] += sdata[tid + 32];
	sdata[tid] += sdata[tid + 16];
	sdata[tid] += sdata[tid + 8];
	sdata[tid] += sdata[tid + 4];
	sdata[tid] += sdata[tid + 2];
	sdata[tid] += sdata[tid + 1];
}

/**
* �Ż�������� reduce3 �д��ڵĶ���ͬ��������ÿ��warpĬ���Զ�ͬ������
* globalInputData  �������ݣ�λ��ȫ���ڴ�
* globalOutputData ������ݣ�λ��ȫ���ڴ�
*/
__global__ void reduce4(float *globalInputData, float *globalOutputData, unsigned int n)
{
	__shared__ float sdata[BLOCK_SIZE];

	// ��������
	unsigned int tid = threadIdx.x;
	unsigned int index = blockIdx.x*(blockDim.x * 2) + threadIdx.x;
	unsigned int indexWithOffset = index + blockDim.x;

	if (index >= n)
	{
		sdata[tid] = 0;
	}
	else if (indexWithOffset >= n)
	{
		sdata[tid] = globalInputData[index];
	}
	else
	{
		sdata[tid] = globalInputData[index] + globalInputData[indexWithOffset];
	}
	
	__syncthreads();

	// �ڹ����ڴ��ж�ÿһ������й�Լ����
	for (unsigned int s = blockDim.x / 2; s>32; s >>= 1)
	{
		if (tid < s)
		{
			sdata[tid] += sdata[tid + s];
		}

		__syncthreads();
	}
	if (tid < 32)
	{
		warpReduce(sdata, tid);
	}

	// �Ѽ������ӹ����ڴ�д��ȫ���ڴ�
	if (tid == 0)
	{
		globalOutputData[blockIdx.x] = sdata[0];
	}
}

/**
* ���� reduce4 ������ʱ��
* fMatrix_Host  ����ͷָ��
* iRow          ��������
* iCol          ��������
* @return       ��
*/
float RuntimeOfReduce4(float *fMatrix_Host, const int iRow, const int iCol)
{
	// ������ά���Ƿ���ȷ
	if (iRow <= 0 || iCol <= 0)
	{
		std::cout << "The size of the matrix is error!" << std::endl;
		return 0.0;
	}

	float *fReuslt = (float*)malloc(sizeof(float));;
	float *fMatrix_Device; // ָ���豸�Դ�
	int iMatrixSize = iRow * iCol; // ����Ԫ�ظ���

	HANDLE_ERROR(cudaMalloc((void**)&fMatrix_Device, iMatrixSize * sizeof(float))); // ���Դ���Ϊ���󿪱ٿռ�
	HANDLE_ERROR(cudaMemcpy(fMatrix_Device, fMatrix_Host, iMatrixSize * sizeof(float), cudaMemcpyHostToDevice)); // �����ݿ������Դ�

	// ��¼��ʼʱ��
	cudaEvent_t start_GPU, end_GPU;
	float elaspsedTime;

	cudaEventCreate(&start_GPU);
	cudaEventCreate(&end_GPU);
	cudaEventRecord(start_GPU, 0);

	for (int i = 1, int iNum = iMatrixSize; i < iMatrixSize; i = 2 * i * BLOCK_SIZE)
	{
		int iBlockNum = (iNum + (2 * BLOCK_SIZE) - 1) / (2 * BLOCK_SIZE);
		reduce4<<<iBlockNum, BLOCK_SIZE>>>(fMatrix_Device, fMatrix_Device, iNum);
		iNum = iBlockNum;
	}

	HANDLE_ERROR(cudaMemcpy(fReuslt, fMatrix_Device, sizeof(float), cudaMemcpyDeviceToHost)); // �����ݿ������ڴ�

	// ��ʱ����
	cudaEventRecord(end_GPU, 0);
	cudaEventSynchronize(end_GPU);
	cudaEventElapsedTime(&elaspsedTime, start_GPU, end_GPU);
	cudaEventDestroy(start_GPU);
	cudaEventDestroy(end_GPU);

	std::cout << "Reduce4 ������ʱ��Ϊ��" << elaspsedTime << "ms." << std::endl;

	HANDLE_ERROR(cudaFree(fMatrix_Device));// �ͷ��Դ�ռ�

	return fReuslt[0];
}
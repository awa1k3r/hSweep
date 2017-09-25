// ALLONE

// Well we definitely need to get rid of the xpts.  Really I need to concentrate on getting the output right so I can check the answers.  Then, if they're right, we can worry about streamlining this. Partly main problem, the keys in the output json are strings. Could read each in and then make it a data frame from dict.

#include <fstream>

#define cudaCheckError(ans) { cudaCheck((ans), __FILE__, __LINE__); }
inline void cudaCheck(cudaError_t code, const char *file, int line, bool abort=false) 
{
   if (code != cudaSuccess) 
   {
      fprintf(stderr,"CUDA error: %s %s %d\n", cudaGetErrorString(code), file, line);
      if (abort) exit(code);
   }
}

#include "heads.h"
#include "decomp.h"
#include "classic.h"
#include "swept.h"

/**
----------------------
    MAIN PART
----------------------
*/

#ifndef HDW
    #define HDW     "hardware/WORKSTATION.json"
#endif

std::vector<int> jsonP(jsons jp, size_t sz)
{
	std::vector <int> outv;
	for(int i=0; i<sz; i++)
	{
		outv.push_back(jp[i].asInt());
	}
	return outv;
}

int main(int argc, char *argv[])
{   
    makeMPI(argc, argv);

    std::string ext = ".json";
    std::string myrank = std::to_string(ranks[1]);
    std::string sout = argv[3];
    sout.append(myrank);
    sout.append(ext); 
    std::string scheme = argv[1];

    std::ifstream hwjson(HDW, std::ifstream::in);
    jsons hwJ;
    hwjson >> hwJ;
    hwjson.close();

    std::vector<int> gpuvec = jsonP(hwJ["GPU"], 1);
    std::vector<int> smGpu(gpuvec.size());
    cGlob.hasGpu = gpuvec[ranks[1]];
    std::partial_sum(gpuvec.begin(), gpuvec.end(), smGpu.begin());
    cGlob.nGpu = smGpu.back();
    smGpu.insert(smGpu.begin(), 0);
    std::vector <int> myGPU = jsonP(hwJ["gpuID"], 1);
    int gpuID = myGPU[ranks[1]];
    
    // Equation, grid, affinity data
    std::ifstream injson(argv[2], std::ifstream::in);
    injson >> inJ;
    injson.close();

    parseArgs(argc, argv);
    initArgs();

    /*  
        Essentially it should associate some unique (UUID?) for the GPU with the CPU. 
        Pretend you now have a (rank, gpu) map in all memory. because you could just retrieve it with a function.
    */
    int strt = cGlob.xcpu * ranks[1] + cGlob.xg * cGlob.hasGpu * smGpu[ranks[1]]; 
    states **state;

    int exSpace = ((int)!scheme.compare("S") * cGlob.ht) + 2;
    int xc = (cGlob.hasGpu) ? cGlob.xcpu/2 : cGlob.xcpu;
    int nrows = (cGlob.hasGpu) ? 3 : 1;
    int xalloc = xc + exSpace;

    std::string pth = string(argv[3]);
    std::vector<int> xpts(strt); //
    std::vector<int> alen(xc);

    if (cGlob.hasGpu)
    {
        cudaSetDevice(gpuID);
        
        state = new states* [3];
        cudaCheckError(cudaHostAlloc((void **) &state[0], xalloc * cGlob.szState, cudaHostAllocDefault));
        cudaCheckError(cudaHostAlloc((void **) &state[1], (cGlob.xg + exSpace) * cGlob.szState, cudaHostAllocDefault));
        cudaCheckError(cudaHostAlloc((void **) &state[2], xalloc * cGlob.szState, cudaHostAllocDefault));

        xpts.push_back(strt + xc);
        alen.push_back(cGlob.xg);
        xpts.push_back(strt + xc + cGlob.xg);
        alen.push_back(xalloc);

        cudaCheckError(cudaMemcpyToSymbol(deqConsts, &heqConsts, sizeof(eqConsts)));

        if (sizeof(REAL)>6) 
        {
            cudaCheckError(cudaDeviceSetSharedMemConfig(cudaSharedMemBankSizeEightByte));
        }
    }
    else 
    {
        state = new states* [1];
        cudaCheckError(cudaHostAlloc((void **) &state[0], xalloc * cGlob.szState, cudaHostAllocDefault));   
    }

    for (int i=0; i<nrows; i++)
    {
        for (int k=0; k<alen[i] + exSpace; k++)  initialState(inJ, state[i], k, xpts[i]);
        for (int k=1; k<=alen[i]; k++)  solutionOutput(state[i], 0.0, k, xpts[i]); 
    }

    // If you have selected scheme I, it will only initialize and output the initial values.
    if (scheme.compare("I"))
    {
        int tstep = 1;
        double timed, tfm;

        MPI_Barrier(MPI_COMM_WORLD);
        if (!ranks[1]) timed = MPI_Wtime();
        cout << "Made it to Calling the function " << endl;

        if (!scheme.compare("C"))
        {
            tfm = classicWrapper(state, xpts, alen, &tstep);
        }
        else if  (!scheme.compare("S"))
        {
            tfm = sweptWrapper(state, xpts, alen, &tstep);
        }
        else
        {
            std::cerr << "Incorrect or no scheme given" << std::endl;
        }

        if (cGlob.hasGpu)
        {
            cudaDeviceSynchronize();
        }

        MPI_Barrier(MPI_COMM_WORLD);
        if (!ranks[1]) timed = (MPI_Wtime() - timed);

        for (int i=0; i<nrows; i++)
        {
            for (int k=1; k<=alen[i]; k++)  solutionOutput(state[i], 0.0, k, xpts[i]);
        }  

        cudaError_t error = cudaGetLastError();
        if(error != cudaSuccess)
        {
            // print the CUDA error message and exit
            printf("CUDA error: %s\n", cudaGetErrorString(error));
            exit(-1);
        }

        if (!ranks[1])
        {
            //READ OUT JSONS
            
            timed *= 1.e6;

            double n_timesteps = tfm/cGlob.dt;

            double per_ts = timed/n_timesteps;

            std::cout << n_timesteps << " timesteps" << std::endl;
            std::cout << "Averaged " << per_ts << " microseconds (us) per timestep" << std::endl;

            // Equation, grid, affinity data
            try {
                std::ifstream tjson(argv[4], std::ifstream::in);
                tjson >> timing;
                tjson.close();
            }
            catch (...) {}

            std::string tpbs = std::to_string(cGlob.tpb);
            std::string nXs = std::to_string(cGlob.nX);
            std::string gpuAs = std::to_string(cGlob.gpuA);
            std::cout << cGlob.gpuA << std::endl;

            std::string spath = pth + "/t" + fspec + ext;
            std::ofstream timejson(spath.c_str(), std::ofstream::trunc);
            timing[tpbs][nXs][gpuAs] = per_ts;
            timejson << timing;
            timejson.close();
        }
    }

    std::string spath = pth + "/s" + fspec + "_" + std::to_string(ranks[1]) + ext;
    std::ofstream soljson(spath.c_str(), std::ofstream::trunc);
    if (!ranks[1]) solution["meta"] = inJ;
    soljson << solution;
    soljson.close();

    endMPI();

    for (int k=0; k<nrows; k++)
    {
        cudaFreeHost(state[k]);
    }
    delete[] state;   
    if (cGlob.hasGpu)
    {
        cudaDeviceSynchronize();
        cudaDeviceReset();
    }
    return 0;
}
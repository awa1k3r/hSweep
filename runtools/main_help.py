'''
    Python Classes and functions for running the cuda programs and
    parsing/plotting the performance data.
'''

import os
import os.path as op
import matplotlib.pyplot as plt

import pandas as pd
import shlex
import subprocess as sp
import collections
import json as j

thispath = op.abspath(op.dirname(__file__))
toppath = op.dirname(thispath)
spath = op.join(toppath, "src")
binpath = op.join(spath, "bin")
rspath = op.join(spath, "rslts")
resultpath = op.join(toppath, "results")
testpath = op.join(spath, "tests")

def numerica(df):
    df.columns = pd.to_numeric(df.columns.values)
    df.index = pd.to_numeric(df.index.values)
    df.sort_index(inplace=True)
    df = df.interpolate()
    return df.sort_index(axis=1)

def dictframes(d, t):
    if t>3:
        return {dk: dictframes(d[dk], t-1) for dk in d.keys()}
    else:
        return numerica(pd.DataFrame(d))

def depth(d, level=1):
    if not isinstance(d, dict) or not d:
        return level
    return max(depth(d[k], level + 1) for k in d)

def readj(f):
    fobj = open(f, 'r')
    fr = fobj.read()
    fobj.close()
    return j.loads(fr)

def undict(d, kind='dict'):
    dp = depth(d)
    if dp>2:
        return {float(dk): undict(d[dk]) for dk in d.keys()}
    else:
        if kind=="tuple":
            return sorted([(int(k), float(v)) for k, v in d.items()])
        elif kind=="dict":
            return {int(k): float(v) for k, v in sorted(d.items())}

def makeList(v):
    if isinstance(v, collections.Iterable) and not isinstance(v, str):
        return v
    else:
        return [v]

#Category: i.e Performance, RunDetail (comp_nprocs_date), plottitle
def saveplot(f, cat, rundetail, titler):
    #Category: i.e regression, Equation: i.e. EulerClassic , plot
    tplotpath = op.join(resultpath, cat)
    if not op.isdir(tplotpath):
        os.mkdir(tplotpath)

    plotpath = op.join(tplotpath, rundetail)
    if not op.isdir(plotpath):
        os.mkdir(plotpath)

    if isinstance(f, collections.Iterable):
        for i, fnow in enumerate(f):
            plotname = op.join(plotpath, titler + str(i) + ".pdf")
            fnow.savefig(plotname, bbox_inches='tight')

    else:
        plotname = op.join(plotpath, titler + ".pdf")
        f.savefig(plotname, bbox_inches='tight')


#Divisions and threads per block need to be lists (even singletons) at least.
def runMPICUDA(exece, nproc, scheme, eqfile, mpiopt="", outdir=" rslts ", eqopt=""):

    runnr = "mpirun -np "
    print("---------------------")
    os.chdir(spath)
    
    execut = runnr + "{0} ".format(nproc) + mpiopt + exece + scheme + eqfile + outdir + eqopt

    print(execut)
    exeStr = shlex.split(execut)
    proc = sp.Popen(exeStr, stdout=sp.PIPE)
    ce, er = proc.communicate()

    ce = ce.decode('utf8') if ce else "None"
    er = er.decode('utf8') if er else "None"

    print(er)

    return ce

# Read notes into a dataFrame. Sort by date and get sha

def getRecentResults(nBack, prints=None):
    rpath = resultpath
    note = readj(op.join(rpath, "notes.json"))
    hfive = op.join(rpath, "rawResults.h5")
    nframe = pd.DataFrame.from_dict(note).T
    nframe = nframe.sort_values("date", ascending=False)
    sha = nframe.index.values[nBack]
    hframe = pd.HDFStore(hfive)
    outframe = hframe[sha]
    hframe.close()
    if prints:
       pr = makeList(prints)
       for ky, it in note:
           print("SHA: ", ky)
           for p in pr:
                if pr in it.keys():
                    print(pr, it[pr])
                else:
                    print(pr, " Is not a key")

    return outframe, note[sha]

#!/bin/bash
# Simulation of an SD7003 airfoil with full Navier Stokes
# The submission script is prepared for Power8 and 4x GPUs

# Note: LSF Data Mover directives are specific to Panther cluster at Daresbury.
#


upload (){
    full_path=`readlink -f sd7003`

    bsub << EOF
#BSUB -J sd7003-up
#BSUB -oo sd7003-up.out
#BSUB -data ${full_path}

bstage in \\
    -src $full_path \\
    -dst sd7003
touch sdready
bstage out -src sdready -tag sdready
EOF
}

run1GPU1node (){
    polynomial_order=${1}
    node_count=1
    gpu_count=1
    thread_per_node=$gpu_count
    thread_count=$(($thread_per_node*$node_count))

    label="sd7003${polynomial_order}GPU1"

    bsub << EOF
#BSUB -J ${label}
#BSUB -oo ${label}.out
#BSUB -q panther
#BSUB -W 8:00
#BSUB -R "span[ptile=${thread_per_node}]"
#BSUB -n ${thread_count}
#BSUB -x
#BSUB -data tag:sdready

rm -rf ${label} 2> /dev/null
cp -r sd7003/ ${label}
cd ${label}

gunzip sd7003.msh.gz 
echo -n "Importing mesh... "
pyfr import sd7003.msh sd7003.pyfrm
echo done.
echo -n "Partitoning mesh... "
pyfr partition ${thread_count} sd7003.pyfrm .
echo done.

export OMP_NUM_THREADS=0
export OMP_PROC_BIND=true
export OMP_PLACES=cores

echo -n "Running... "
pyfr run --backend cuda \\
    sd7003.pyfrm \\
    sd7003.ini
EOF
}

run4GPU (){
    node_count=${1}
    polynomial_order=${2}
    gpu_count=4
    thread_per_node=$gpu_count
    thread_count=$(($thread_per_node*$node_count))

    label="sd7003_n${node_count}"

    bsub << EOF
#BSUB -J ${label}
#BSUB -oo ${label}.out
#BSUB -q PantherBenchmark
#BSUB -W 8:00
#BSUB -R "span[ptile=${thread_per_node}]"
#BSUB -n ${thread_count}
#BSUB -x
#BSUB -data tag:sdready

ulimit -s 10240

rm -rf ${label} 2> /dev/null
cp -r sd7003/ ${label}
cd ${label}

gunzip sd7003.msh.gz 
echo -n "Importing mesh... "
pyfr import sd7003.msh sd7003.pyfrm
echo done.
echo -n "Partitoning mesh... "
pyfr partition ${thread_count} sd7003.pyfrm .
echo done.

export OMP_NUM_THREADS=0
# export OMP_PROC_BIND=true
# export OMP_PLACES=cores

echo "Running... "
mpirun -report-bindings -display-map -display-allocation \\
    -bind-to core -map-by ppr:2:socket -rank-by core \\
    pyfr --verbose run --backend cuda \\
    sd7003.pyfrm \\
    sd7003.ini

EOF
}

bdata tags clean sdready -dmd panther
sleep 1
upload
run1GPU1node
for n in 1 2 4 8 16 28 29 30;
do
    run4GPU $n
done

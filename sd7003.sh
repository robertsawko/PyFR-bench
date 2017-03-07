#!/bin/bash
# Simulation of an SD7003 airfoil with full Navier Stokes

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
#BSUB -q excl
#BSUB -W 24:00
#BSUB -R "select[ngpus=4] rusage[ngpus_shared=20]"
#BSUB -R "span[ptile=${thread_per_node}]"
#BSUB -n ${thread_count}
#BSUB -x

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

echo -n "Running... "
perf stat pyfr run --backend cuda \\
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
#BSUB -q excl
#BSUB -W 2:00
#BSUB -R "span[ptile=${thread_per_node}]"
#BSUB -R "select[ngpus=4] rusage[ngpus_shared=20]"
#BSUB -n ${thread_count}
#BSUB -x

ulimit -s 10240

rm -rf ${label} 2> /dev/null
cp -r sd7003/ ${label}
cd ${label}

export PATH=$PATH

gunzip sd7003.msh.gz 
echo -n "Importing mesh... "
pyfr import sd7003.msh sd7003.pyfrm
echo done.
echo -n "Partitoning mesh... "
pyfr partition ${thread_count} sd7003.pyfrm .
echo done.

echo "Running... "
perf stat mpirun \\
    -report-bindings -display-map -display-allocation \\
    -np $thread_count \\
    -bind-to hwthread -map-by ppr:2:socket -rank-by socket \\
    pyfr run --backend cuda \\
    sd7003.pyfrm \\
    sd7003.ini

EOF
}

# run1GPU1node
for n in 1 2 4 8 16 32;
do
    run4GPU $n
done

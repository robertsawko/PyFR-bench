#!/bin/bash
# Simulation of an SD7003 airfoil with full Navier Stokes

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

    label="ivp${polynomial_order}GPU1"

    bsub << EOF
#BSUB -J ${label}
#BSUB -oo ${label}.out
#BSUB -q panther
#BSUB -W 24:00
#BSUB -R "span[ptile=${thread_per_node}]"
#BSUB -n ${thread_count}
#BSUB -x
#BSUB -data tag:sdready

rm -rf ${label} 2> /dev/null
cp -r /p${polynomial_order} ${label}
cd ${label}

mesh_file=\`ls *.msh\`

pyfr import \${mesh_file} euler_vortex_2d.pyfrm

pyfr run --backend cuda \\
    euler_vortex_2d.pyfrm \\
    euler_vortex_2d.ini
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
#BSUB -q panther
#BSUB -W 24:00
#BSUB -R "span[ptile=${thread_per_node}] affinity[core(1)]"
#BSUB -n ${thread_count}
#BSUB -x
#BSUB -data tag:sdready

rm -rf ${label} 2> /dev/null
cp -r sd7003/ ${label}
cd ${label}

gunzip sd7003.msh.gz 
echo -n "Importing mesh... "
pyfr import sd7003.msh sd7003.pyfrm
echo done
echo -n "Partitoning mesh... "
pyfr partition ${thread_count} sd7003.pyfrm .
echo done

export OMP_NUM_THREADS=0
export OMP_PROC_BIND=true
export OMP_PLACES=cores

export HYDRA_TOPO_DEBUG=1
export MV2_SHOW_ENV_INFO=2
export MV2_SHOW_CPU_BINDING=1

export MV2_CPU_BINDING_POLICY=scatter

echo -n "Running... "
mpirun \\
    pyfr run --backend cuda \\
    sd7003.pyfrm \\
    sd7003.ini
EOF
}

bdata tags clean sdready -dmd panther
sleep 1
upload
for n in 1 2 4 8 16;
do
    run4GPU $n $p
done

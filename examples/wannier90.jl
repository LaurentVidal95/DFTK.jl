# # DFTK - Wannier90 interface
#
# DFTK features an interface with the program
# [Wannier90](http://www.wannier.org/),
# in order to compute maximally-localized Wannier functions (MLWFs)
# from an initial self consistent field calculation.
# All processes are handled by calling the routine `run_wannier90`.
#
# This example shows how to obtain the MLWFs corresponding
# to the first eight bands of silicon. Since the bands 5 to 8 are entangled,
# 12 bands are first computed to obtain 8 MLWFs by a disantanglement procedure.
# We first perfom a SCF calculation, which is for the most part identical to the
# regular case.
#
# !!! warning "Compatibility asks for a specific setup"
#     The wannier90 input file, `.win`, will correspond to the studied system only if
#     the number of ``k`` points in input is the same as in output.
#     Since DFTK reduces by default the number of ``k`` points by
#     symmetry one must specify `use_symmetry = false`
#     in the creation of the plane wave basis.

using DFTK

a = 10.26
lattice = a / 2*[[-1.  0. -1.];
                 [ 0   1.  1.];
                 [ 1   1.  0.]]

Si = ElementPsp(:Si, psp=load_psp("hgh/pbe/Si-q4"))
atoms = [ Si => [zeros(3), 0.25*[-1,3,-1]] ]

model = model_PBE(lattice,atoms)

kgrid = [4,4,4]
Ecut = 20
basis = PlaneWaveBasis(model, Ecut; kgrid=kgrid, use_symmetry=false)

scfres = self_consistent_field(basis, tol=1e-12, n_bands = 12);

# !!! note "Extra bands."
#     DFTK automatically adds 3 extra non converged bands for the scf calculation.
#     The number of bands appearing in the win file will then be `n_bands+3`.
#     You can disable it at your own risk with `n_ep_extra = 0` in the
#     call to `self_consistent_field`.
#
# We now use the `run_wannier90` routine to generate all needed files
# and perform the wannierization procedure. In Wannier90's convention, all files are
# named with the same prefix and only differ by their types.
# The argument nedded by `run_wannier90` are this prefix, the result
# of the scf computation `scfres` and the number of wanted MLWFs,
# 8 in our case.

mkdir("wannier90_out")
prefix = "wannier90_out/Si"
num_wann = 8

# We now simply call:

run_wannier90(prefix, scfres, num_wann,
              bands_plot=true,
              num_print_cycles=50, num_iter=500,
              dis_win_max       = 17.185257,
              dis_froz_max      = 6.8318033,
              dis_num_iter      = 120,
              dis_mix_ratio     = 1.0)

# Remark that the parameters of the disentanglement have been added as
# key word arguments. All optional parameters can be added as such.
# Also note that `bands_plot = true` generates the ``k``-point path
# using the [Pymatgen](https://pymatgen.org/) python library in order
# to generate the bands plot with the MLWFs. The output is contained in
# the `wannier90_out/Si.wout` file. See the [Wannier90](http://www.wannier.org/)
# documentation to exploit these data.

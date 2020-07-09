# Very basic setup, useful for testing
using DFTK
using PyPlot
using FFTW

BLAS.set_num_threads(4)
FFTW.set_num_threads(4)

include("perturbations.jl")
include("self_energy.jl")

# setting up the model on the fine grid
a = 10.26  # Silicon lattice constant in Bohr
lattice = a / 2 * [[0 1 1.];
                   [1 0 1.];
                   [1 1 0.]]
Si = ElementPsp(:Si, psp=load_psp("hgh/lda/Si-q4"))
atoms = [Si => [ones(3)/8, -ones(3)/8]]
model = model_atomic(lattice, atoms, n_electrons=2)
kgrid = [1, 1, 1]  # k-point grid (Regular Monkhorst-Pack grid)
kcoords, ksymops = bzmesh_ir_wedge(kgrid, model.symops)
terms = ["Kinetic", "AtomicLocal", "AtomicNonlocal"]

Ecut = 50          # kinetic energy cutoff in Hartree
basis = PlaneWaveBasis(model, Ecut; kgrid=kgrid)

# parameters
tol = 1e-10
avg = true
Gvec = [1,0,0]

# reference computation
println("---------------------")
println("Reference computation")
scfres = self_consistent_field(basis, tol=tol)
nrj_ref = sum([scfres.energies[term] for term in terms])
λ_ref = scfres.eigenvalues[1][1]
idx_Gvec = findfirst(isequal(Gvec), G_vectors(basis.kpoints[1]))
ψ_ref = scfres.ψ[1][idx_Gvec, 1]
#  ψ_ref = scfres.ψ

Ecuts_list = 6:2:18

err_coarse = []
err_pert = []
err_se = []

err_λ_fine = []
err_λ_se = []
err_λ_coarse = []
err_λ3_pert = []
err_λ2_pert = []
err_λsp1 = []
err_λsp2 = []
err_λsp = []

err_ψ_coarse = []
err_ψ_fine = []
err_ψ_pert = []
err_ψsp = []
err_ψ_se = []

for Ecuts in Ecuts_list

    println("---------------------")
    println("---------------------")
    println("Ecuts = $(Ecuts)")

    global err_coarse, err_pert, err_se
    global err_λ_se, err_λ_coarse, err_λ2_pert, err_λ3_pert, err_λ_fine
    global err_λsp, err_λsp1, err_λsp2
    global err_ψ_coarse, err_ψ_pert, err_ψsp, err_ψ_se, err_ψ_fine
    global basis

    # setting up the coarse grid
    println("---------------------")
    println("setting coarse grid model")
    Ecutf = 2.5 * Ecuts
    basis_coarse = PlaneWaveBasis(model, Ecuts; kgrid=kgrid)
    basis_fine = PlaneWaveBasis(model, Ecutf; kgrid=kgrid)
    nrj, ham = energy_hamiltonian(basis_fine, nothing, scfres.occupation)
    idx_Gvec = findfirst(isequal(Gvec), G_vectors(basis_coarse.kpoints[1]))
    idx_Gvec_fine = findfirst(isequal(Gvec), G_vectors(basis_fine.kpoints[1]))

    # interpolation between coarse and fine grid
    H = Array(ham.blocks[1])
    println("dense hamiltonian built")
    idcs, idcs_cmplt = DFTK.grid_interpolation_indices(basis_coarse, basis_fine)
    Hs = H[idcs[1], idcs[1]]

    # computation self-energy correction
    Wsl = H[idcs[1], idcs_cmplt[1]]
    Hl = H[idcs_cmplt[1], idcs_cmplt[1]]
    kpt_fine = basis_fine.kpoints[1]
    kin = Diagonal([sum(abs2, basis_fine.model.recip_lattice * (G + kpt_fine.coordinate))
                    for G in G_vectors(kpt_fine)] ./ 2)[idcs_cmplt[1], idcs_cmplt[1]]
    avgW = Diagonal(compute_avg(basis_fine, ham)[1])[idcs_cmplt[1], idcs_cmplt[1]]
    Σ(λ) = Wsl * ((λ*I - (kin + avgW)) \ Wsl')

    # diag on the coarse grid
    println("---------------------")
    println("diag on the coarse grid")
    Es, Vs = eigen(Hs)
    ψs = [Vs[:, 1:4]]
    ρs = compute_density(basis_coarse, ψs, scfres.occupation)
    nrj_coarse, hams = energy_hamiltonian(basis_coarse, ψs, scfres.occupation; ρ=ρs)
    push!(err_coarse, abs(sum([nrj_coarse[term] for term in terms]) - nrj_ref))
    push!(err_λ_coarse, abs(Es[1] - λ_ref))
    push!(err_ψ_coarse, abs(abs2(ψs[1][idx_Gvec, 1]) - abs2(ψ_ref)))
    #  ψs_ref, _ = DFTK.interpolate_blochwave(ψs, basis_coarse, basis)
    #  push!(err_ψ_coarse, norm(ψs_ref[1][:,1]*ψs_ref[1][:,1]'
    #                           - ψ_ref[1][:,1]*ψ_ref[1][:,1]'))

    # diag on the fine grid
    println("---------------------")
    println("diag on the fine grid")
    E, V = eigen(H)
    ψ = [V[:, 1:4]]
    ρ = compute_density(basis_fine, ψ, scfres.occupation)
    push!(err_λ_fine, abs(E[1] - λ_ref))
    push!(err_ψ_fine, abs(abs2(ψ[1][idx_Gvec_fine, 1]) - abs2(ψ_ref)))

    # Rayleigh coefficients to compare with perturbations
    println("---------------------")
    println("Rayleigh-coeff with self-energy")
    Esp1 = ψs[1]' * (Hs+Σ(Es[1])) * ψs[1]
    push!(err_λsp1, abs(Esp1[1] - λ_ref))
    Esp2 = ψs[1]' * (Hs+Σ(Esp1[1])) * ψs[1]
    push!(err_λsp2, abs(Esp2[1] - λ_ref))

    # perturbation
    println("---------------------")
    println("Perturbation")
    scfres_coarse = self_consistent_field(basis_coarse, tol=tol, callback=info->nothing)
    Ep_fine, ψp_fine, ρp_fine, egvalp2, egvalp3, egvalp_rr, forcesp_fine, Ep2_fine = perturbation(basis_coarse, kcoords, ksymops, scfres_coarse, 2.5*Ecuts)
    push!(err_pert, abs(sum([Ep_fine[term] for term in terms]) - nrj_ref))
    push!(err_λ3_pert, abs(egvalp3[1][1] - λ_ref))
    push!(err_λ2_pert, abs(egvalp2[1][1] - λ_ref))
    push!(err_ψ_pert, abs(abs2(ψp_fine[1][idx_Gvec_fine, 1]) - abs2(ψ_ref)))
    #  ψp_ref, _ = DFTK.interpolate_blochwave(ψp_fine, basis_fine, basis)
    #  push!(err_ψ_pert, norm(ψp_ref[1][:,1]*ψp_ref[1][:,1]'
    #                         - ψ_ref[1][:,1]*ψ_ref[1][:,1]'))

    # diagonalization of H + Σ(λ)
    println("---------------------")
    println("diagonalization of H + Σ(λ)")
    Esp, Vsp = eigen( Hs + Σ(Es[1]) )
    ψsp = [Vsp[:, 1:4]]
    push!(err_λsp, abs(Esp[1] - λ_ref))
    push!(err_ψsp, abs(abs2(ψsp[1][idx_Gvec, 1]) - abs2(ψ_ref)))
    #  ψsp, _ = DFTK.interpolate_blochwave(ψsp, basis_coarse, basis)
    #  push!(err_ψsp, norm(ψsp[1][:,1]*ψsp[1][:,1]'
    #                      - ψ_ref[1][:,1]*ψ_ref[1][:,1]'))

    # self-energy SCF
    println("---------------------")
    println("Self-energy SCF")
    λ, ψ_se, nrj_se, _ = self_energy_SCF(Hs, basis_coarse, Σ, Es[1]; maxiter=100)
    push!(err_se, abs(sum([nrj_se[term] for term in terms]) - nrj_ref))
    push!(err_λ_se, abs(λ - λ_ref))
    push!(err_ψ_se, abs(abs2(ψ_se[1][idx_Gvec, 1]) - abs2(ψ_ref)))
    #  ψ_se_ref, _ = DFTK.interpolate_blochwave(ψ_se, basis_coarse, basis)
    #  push!(err_ψ_se, norm(ψ_se_ref[1][:,1]*ψ_se_ref[1][:,1]'
    #                       - ψ_ref[1][:,1]*ψ_ref[1][:,1]'))

end

# plotting
#  figure()
#  semilogy(Ecuts_list, err_coarse, "x-", label="coarse diag")
#  semilogy(Ecuts_list, err_pert, "x-", label="pert")
#  semilogy(Ecuts_list, err_se, "x-", label="se")
#  ylabel("error")
#  xlabel("Ecut")
#  legend()

figure()
semilogy(Ecuts_list, err_λ_coarse, "x-", label="λ coarse diag")
semilogy(Ecuts_list, err_λ_fine, "x-", label="λ fine diag")
semilogy(Ecuts_list, err_λ2_pert, "x-", label="λ2 pert")
semilogy(Ecuts_list, err_λsp1, "x-", label="λ2 rayleigh with se")
semilogy(Ecuts_list, err_λ3_pert, "x-", label="λ3 pert")
semilogy(Ecuts_list, err_λsp2, "x-", label="λ3 rayleigh with se")
semilogy(Ecuts_list, err_λsp, "x-", label="λ from Hs + Σ(λ0)")
semilogy(Ecuts_list, err_λ_se, "x-", label="λ se")
xlabel("Ecut")
ylabel("error on λ")
legend()

figure()
semilogy(Ecuts_list, err_ψ_coarse, "x-", label="G coarse diag")
semilogy(Ecuts_list, err_ψ_fine, "x-", label="G fine diag")
semilogy(Ecuts_list, err_ψ_pert, "x-", label="G pert")
semilogy(Ecuts_list, err_ψsp, "x-", label="G from Hs + Σ(λ0)")
semilogy(Ecuts_list, err_ψ_se, "x-", label="G se")
xlabel("Ecut")
ylabel("error on ψ$(Gvec) = $(abs2(ψ_ref))")
legend()


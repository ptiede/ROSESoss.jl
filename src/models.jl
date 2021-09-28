
#Turn off precompilations because of GG bug https://github.com/cscherrer/Soss.jl/issues/267
const fwhmfac = 2*sqrt(2*log(2))

using Soss
using ROSE
using MeasureTheory
import Distributions as Dists


gamps = @model stations, spriors begin
    #Gain amps
    σ ~ For(eachindex(spriors)) do i
        Dists.LogNormal(0.0, spriors[i])
    end
    return NamedTuple{stations}(σ)
end

gphases = @model stations begin
    σ ~ Dists.truncated(Dists.Normal(0.0, π), -π, π) |> iid(length(stations))
    return NamedTuple{stations}(σ)
end

function amp_gains(img, g1,g2, u, v)
    return g1*g2*ROSE.visibility_amplitude(img, u, v)
end

function _vamps(img, g, s1, s2, uamp, vamp)
    vm = similar(uamp)
    for i in eachindex(uamp)
        vm[i] = amp_gains(img,
                            g[s1[i]],
                            g[s2[i]],
                            uamp[i],
                            vamp[i]
                            )
    end
    return vm
end


va = @model image, gamps, uamp, vamp, s1, s2, erramp begin
    img ~ image
    g ~ gamps
    vm = _vamps(img, g, s1, s2, uamp, vamp)
    amp ~ Dists.MvNormal(vm, erramp)
end

vacp = @model image, gamps, uamp, vamp, s1, s2, erramp,
               u1cp, v1cp, u2cp, v2cp, u3cp, v3cp, errcp begin

    img ~ image
    g ~ gamps
    vm = _vamps(img, g, s1, s2, uamp, vamp)
    amp ~ Dists.MvNormal(vm, erramp)

    cp = ROSE.closure_phase.(Ref(img),
                            u1cp,
                            v1cp,
                            u2cp,
                            v2cp,
                            u3cp,
                            v3cp)

    cphase ~ For(eachindex(cp)) do i
        ROSE.CPVonMises(cp[i], errcp[i])
    end

end

function vis_gains(img, ga1,ga2, gp1,gp2, u, v)
    Δθ = gp1 - gp2
    s,c = sincos(Δθ)
    g1 = ga1
    g2 = ga2
    vis = visibility(img, u, v)
    vr = g1*g2*(real(vis)*c + imag(vis)*s)
    vi = g1*g2*(-real(vis)*s + imag(vis)*c)
    return vr+vi*im
end

function _vism(img, ga, gp, s1, s2, u, v)
    vm = similar(u,Complex{eltype(u)})
    for i in eachindex(u)
        vm[i] = vis_gains(img,
                          ga[s1[i]],
                          ga[s2[i]],
                          gp[s1[i]],
                          gp[s2[i]],
                          u[i],
                          v[i]
                        )
    end
    return vm
end



vis = @model image, gamps, gphases, u, v, s1, s2, error begin
    img ~ image
    ga ~ gamps
    gp ~ gphases
    vis = _vism(img, ga, gp, s1, s2, u, v)

    visr ~ Dists.MvNormal(real.(vis), err)
    visi ~ Dists.MvNormal(imag.(vis), err)

end


lcacp = @model image,
               u1a,v1a,u2a,v2a,u3a,v3a,u4a,v4a,errcamp,
               u1p,v1p,u2p,v2p,u3p,v3p,errcp begin
    img ~ image

    lcamp ~ For(eachindex(errcamp)) do i
        ca = ROSE.logclosure_amplitude(img,
                                      u1a[i], v1a[i],
                                      u2a[i], v2a[i],
                                      u3a[i], v3a[i],
                                      u4a[i], v4a[i],
                                    )
        Dists.Normal(ca, errcamp[i])
    end

    cphase ~ For(eachindex(u1cp, errcp)) do i
        mphase = ROSE.closure_phase(img,
                                    u1cp[i],
                                    v1cp[i],
                                    u2cp[i],
                                    v2cp[i],
                                    u3cp[i],
                                    v3cp[i]
                                )
        ROSE.CPVonMises(mphase, errcp[i])
    end
end

#=
mringwb = @model N, M, fov begin
    diam ~ Dists.Uniform(25.0, 85.0)
    fwhm ~ Dists.Uniform(1.0, 40.0)
    rad = diam/2
    σ = fwhm/fwhmfac

    ma ~ Dists.Uniform(0.0, 0.5) |> iid(N)
    mp ~ Dists.Uniform(-1π, 1π) |> iid(N)
    α = ma.*cos.(mp)
    β = ma.*sin.(mp)

    #Fraction of floor flux
    floor ~ Dists.Uniform(0.0, 1.0)
    f ~ Dists.Uniform(0.8, 1.2)
    mring = renormed(ROSE.MRing{N}(rad, α, β), f-f*floor)
    rimg = smoothed(mring,σ)

    coeff ~ Dists.Dirichlet(fill(M*M, 1.0))
    ϵ ~ Dists.LogNormal(0.0, 0.1)
    bimg = renormed(stretched(ROSE.RImage(coeff, ROSE.SqExpKernel(ϵ)),fov,fov), f*floor)
    img = rimg+bimg
    return img
end
=#
mring = @model N begin
    diam ~ Dists.Uniform(25.0, 85.0)
    fwhm ~ Dists.Uniform(1.0, 40.0)
    rad = diam/2
    σ = fwhm/fwhmfac

    ma ~ Dists.Uniform(0.0, 0.5) |> iid(N)
    mp ~ Dists.Uniform(-1π, 1π) |> iid(N)
    α = ma.*cos.(mp)
    β = ma.*sin.(mp)

    f ~ Dists.Uniform(0.8, 1.2)
    mring = renormed(ROSE.MRing{N}(rad, α, β), f)
    img = smoothed(mring,σ)
    return img
end

mringwfloor = @model N begin
    diam ~ Dists.Uniform(25.0, 85.0)
    fwhm ~ Dists.Uniform(1.0, 40.0)
    rad = diam/2
    σ = fwhm/fwhmfac

    ma ~ Dists.Uniform(0.0, 0.5) |> iid(N)
    mp ~ Dists.Uniform(-1π, 1π) |> iid(N)
    α = ma.*cos.(mp)
    β = ma.*sin.(mp)

    #Fraction of floor flux
    floor ~ Dists.Uniform(0.0, 1.0)
    f ~ Dists.Uniform(0.8, 1.2)

    mring = renormed(ROSE.MRing{N}(rad, α, β), f*(1-floor))
    disk = renormed(stretched(ROSE.Disk(), rad, rad), f*floor)
    img = smoothed(mring+disk,σ)
    return img
end

mringwgfloor = @model N begin
    diam ~ Dists.Uniform(25.0, 85.0)
    fwhm ~ Dists.Uniform(1.0, 40.0)
    rad = diam/2
    σ = fwhm/fwhmfac

    ma ~ Dists.Uniform(0.0, 0.5) |> iid(N)
    mp ~ Dists.Uniform(-1π, 1π) |> iid(N)
    α = ma.*cos.(mp)
    β = ma.*sin.(mp)

    #Fraction of floor flux
    floor ~ Dists.Uniform(0.0, 1.0)
    f ~ Dists.Uniform(0.8, 1.2)
    dg ~ Dists.Uniform(10.0, 100.0)
    rg = dg/2
    mring = smoothed(renormed(ROSE.MRing{N}(rad, α, β), f*(1-floor)), σ)
    g = renormed(stretched(ROSE.Gaussian(), rg, rg), f*floor)
    img = mring + g
    return img
end


smring = @model N begin
    diam ~ Dists.Uniform(25.0, 85.0)
    fwhm ~ Dists.Uniform(1.0, 40.0)
    rad = diam/2
    σ = fwhm/fwhmfac

    ma ~ Dists.Uniform(0.0, 0.5) |> iid(N)
    mp ~ Dists.Uniform(-1π, 1π) |> iid(N)
    α = ma.*cos.(mp)
    β = ma.*sin.(mp)

    #Stretch
    τ ~ Dists.Uniform( 0.0, 0.5)
    ξτ ~ Dists.Uniform(-π/2, π/2)
    scx = 1/sqrt(1-τ)
    scy = sqrt(1-τ)

    f ~ Dists.Uniform(0.8, 1.2)

    mring = renormed(ROSE.MRing{N}(rad, α, β), f)
    img = smoothed(rotated(stretched(mring,scx,scy),ξτ),σ)
    return img
end


smringwfloor = @model N begin
    diam ~ Dists.Uniform(25.0, 85.0)
    fwhm ~ Dists.Uniform(1.0, 40.0)
    rad = diam/2
    σ = fwhm/fwhmfac

    ma ~ Dists.Uniform(0.0, 0.5) |> iid(N)
    mp ~ Dists.Uniform(-1π, 1π) |> iid(N)
    α = ma.*cos.(mp)
    β = ma.*sin.(mp)

    #Stretch
    τ ~ Dists.Uniform(0.0, 0.5)
    ξτ ~ Dists.Uniform(-π/2, π/2)
    scx = 1/sqrt(1-τ)
    scy = sqrt(1-τ)


    #Fraction of floor flux
    floor ~ Dists.Uniform(0.0, 1.0)
    f ~ Dists.Uniform(0.8, 1.2)

    mring = renormed(ROSE.MRing{N}(rad, α, β), f*(1-floor))
    disk = renormed(stretched(ROSE.Disk(), rad, rad), f*floor)
    img = smoothed(rotated(stretched(mring+disk,scx,scy),ξτ),σ)
    return img
end

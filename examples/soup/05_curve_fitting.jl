#!/usr/bin/env julia
using QuickEnv
using SpecialFunctions
using LsqFit

@. model(x, p) = p[1] * erf(p[2] * x)

function (@main)(args)
    xdata = range(-2.0, 2.0, length=30)
    ydata = 2.5 .* erf.(1.2 .* xdata) .+ 0.05 .* randn(length(xdata))
    p0 = [1.0, 1.0]
    fit = curve_fit(model, collect(xdata), ydata, p0)
    println("[05_curve_fitting] Fitted erf params: p[1]=$(round(fit.param[1], digits=3)), p[2]=$(round(fit.param[2], digits=3))")
    return 0
end

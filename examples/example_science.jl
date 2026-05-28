#!/usr/bin/env julia
using QuickEnv # create: science, silent

using Plots
using SpecialFunctions
using LsqFit

# Define the model function (Bessel function fit: y = a * J_0(b * x))
model(x, p) = p[1] .* besselj.(0, p[2] .* x)

function (@main)(args)
    # Ensure output directory exists
    out_dir = joinpath(@__DIR__, "output")
    isdir(out_dir) || mkdir(out_dir)

    # Default to gr() backend as per guidelines
    gr()

    # 1. Generate synthetic noisy data using SpecialFunctions.besselj
    xdata = range(0.1, 10.0, length=50)
    # True parameters: amplitude = 2.5, frequency = 1.2
    ydata = model(xdata, [2.5, 1.2]) + 0.15 * randn(length(xdata))

    # 2. Perform non-linear curve fitting using LsqFit.curve_fit
    # Initial guess: amplitude = 2.0, frequency = 1.0
    p0 = [2.0, 1.0]
    fit = curve_fit(model, xdata, ydata, p0)
    fitted_params = fit.param

    # Generate smooth data for the fitted curve plot
    xfit = range(0.1, 10.0, length=200)
    yfit = model(xfit, fitted_params)

    # 3. Plot the data points and the fitted Bessel curve using Plots
    p = scatter(xdata, ydata, label="Noisy Data (Bessel)", title="Scientific Curve Fit",
                xlabel="X-Axis", ylabel="Y-Axis", markercolor=:red, markersize=5)
    plot!(p, xfit, yfit, label="Fitted Bessel (a=$(round(fitted_params[1], digits=2)), b=$(round(fitted_params[2], digits=2)))",
          linecolor=:blue, linewidth=2.5)

    # Save the output image as PDF (using Cairo PDF generator)
    out_file = joinpath(out_dir, "science_plot.pdf")
    savefig(p, out_file)

    # Print the created file name to standard output
    println(out_file)

    return 0
end

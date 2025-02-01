using Oceananigans
using Oceananigans.Units

using ClimaOcean
using ClimaOcean.DataWrangling: ECCO4Monthly
using OrthogonalSphericalShellGrids: TripolarGrid

using CFTime
using Dates
using Printf

make_visualization = true
arch = CPU()
Nx = 180
Ny = 90
Nz = 20

z_faces = exponential_z_faces(Nz=10, depth=6000, h=30)

underlying_grid = TripolarGrid(arch; size=(Nx, Ny, Nz), halo=(7, 7, 7), z=z_faces)
bottom_height = regrid_bathymetry(underlying_grid)
grid = ImmersedBoundaryGrid(underlying_grid, GridFittedBottom(bottom_height))

dates = DateTimeProlepticGregorian(1993, 1, 1) : Month(1) : DateTimeProlepticGregorian(1993, 12, 1)
temperature = ECCOMetadata(:temperature, dates, ECCO4Monthly())
salinity = ECCOMetadata(:salinity, dates, ECCO4Monthly())

restoring_rate  = 1/10days
mask = LinearlyTaperedPolarMask(southern=(-80, -70), northern=(70, 90))
FT = ECCORestoring(temperature, grid; mask, rate=restoring_rate)
FS = ECCORestoring(salinity, grid; mask, rate=restoring_rate)

ocean = ocean_simulation(grid; forcing=(T=FT, S=FT))

set!(ocean.model, T=ECCOMetadata(:temperature; dates=first(dates)),
                  S=ECCOMetadata(:salinity; dates=first(dates)))

radiation  = Radiation(arch)
atmosphere = JRA55PrescribedAtmosphere(arch; backend=JRA55NetCDFBackend(20))
coupled_model = OceanSeaIceModel(ocean; atmosphere, radiation) 
simulation = Simulation(coupled_model; Δt=20minutes, stop_iteration=100) #stop_time=30days)

wall_time = Ref(time_ns())

function progress(sim)
    ocean = sim.model.ocean
    u, v, w = ocean.model.velocities
    T = ocean.model.tracers.T
    Tmax = maximum(interior(T))
    Tmin = minimum(interior(T))
    umax = (maximum(abs, interior(u)), maximum(abs, interior(v)), maximum(abs, interior(w)))
    step_time = 1e-9 * (time_ns() - wall_time[])

    @info @sprintf("Time: %s, n: %d, Δt: %s, max|u|: (%.2e, %.2e, %.2e) m s⁻¹, \
                   extrema(T): (%.2f, %.2f) ᵒC, wall time: %s \n",
                   prettytime(sim), iteration(sim), prettytime(sim.Δt),
                   umax..., Tmax, Tmin, prettytime(step_time))

    wall_time[] = time_ns()

    return nothing
end

add_callback!(simulation, progress, IterationInterval(10))

run!(simulation)

if make_visualization
    # A simple visualization
    using GLMakie

    fig = Figure(size=(600, 700))
    axT = Axis(fig[1, 1])
    axu = Axis(fig[2, 1])

    T = ocean.model.tracers.T
    u = ocean.model.velocities.u
    Nz = size(grid, 3)
    heatmap!(axT, interior(T, :, :, Nz))
    heatmap!(axu, interior(u, :, :, Nz))
    display(fig)
end

# SimpleABM
A simple agent-based model that simulates the transition to a renewable energy system.

# License
This is a Julia port of a Python model originally written by [Jinxi Yang](https://www.chalmers.se/en/staff/Pages/jinxi-yang.aspx) at Chalmers University of Technology. Please contact her if you want to modify or cite the model. To be clear: the code in this repository has not yet been released under an open license.

# Installation
Install and start Julia. Then type this (it may take a minute to build the registry the first time):

```
julia> Pkg.add("https://github.com/niclasmattsson/SimpleABM")
```

# Running the model

To simulate 70 years using default parameters:

```
julia> using SimpleABM

julia> capac, invest = runmodel(70);

```
Then examine the output variables `capac` and `invest`. Capacities are in MW with one row per year and one column per technology, in the order [wind, solar, nuclear, coal, gas]. Investments are listed with one row per plant investment, so several investments may take place each year. Investments with negative years represent the existing energy system at the beginning of the simulation at year 1.

Here's how to change default parameters (here four companies with different hurdle rates, cheaper solar):

```
julia> capac, invest = runmodel(70, hurdlerates=[0.04, 0.06, 0.08, 0.1], investcost=[1500., 400., 6000., 1450., 900.]);
```

All parameters defined in `defaults = Dict(...)` at the beginning of `read_input_data()` can be changed in this way.







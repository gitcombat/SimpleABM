module SimpleABM

using DelimitedFiles, Random, UnPack

export read_input_data, read_old_investments, marketprice, annualprofit, profitability, runmodel

function read_input_data(; args...)
    defaults = Dict(
        :tech => ["wind", "solar", "nuclear", "coal", "gas"],
        :varcost => [0, 0, 10., 20., 45.],                  # $/MWh
        :investcost => [1500., 800., 6000., 1450., 900.],   # $/kW 
        :lifetime => [25, 25, 40, 40, 30],                  # years
        :emissionfactor => [0, 0, 0, 1, 0.45],              # ton CO2/MWh
        :refprice => 30.0,          # $/MWh
        :elasticity => -0.05,       # price elasticity of demand
        :varcost_biogas => 100.0,   # $/MWh
        :plantsize => 500.0,        # MW
        :hurdlerates => [0.06, 0.08, 0.10]      # also determines number of companies
    )
    params = merge(defaults, args)
    @unpack tech, varcost, investcost, lifetime, emissionfactor, refprice, elasticity,
                varcost_biogas, plantsize, hurdlerates = params

    thisfolder = dirname(@__FILE__)
    data = readdlm("$thisfolder/slice_data.csv", ',', skipstart=1)
    demand = data[:, 2]                         # MW
    hoursperslice = data[:, 3]                  # h/slice
    availability = permutedims(data[:, 4:8])    # tech x slice
    techindex = Dict(t => i for (i,t) in enumerate(tech))

    # new NamedTuple syntax in Julia 1.5: https://github.com/JuliaLang/julia/pull/34331
    # (so functions that are passed parameter objects are type stable)
    return (; tech, techindex, investcost, varcost, lifetime, emissionfactor, refprice, elasticity,
                varcost_biogas, plantsize, hurdlerates, demand, availability, hoursperslice)
end

struct Investment
    tech::String
    techindex::Int
    capacity::Float64
    year::Int
end

function read_old_investments(params)
    @unpack varcost, techindex = params
    plants = Investment[]
    startcapacity = zeros(length(varcost))
    thisfolder = dirname(@__FILE__)
    data = readdlm("$thisfolder/oldinvestments.csv", ',', skipstart=1)
    for (tech, capacity, year) in eachrow(data)
        index = techindex[tech]
        startcapacity[index] += capacity
        push!(plants, Investment(tech, index, capacity, year))
    end
    reverse!(plants)    # newest plants are at the top in the file
    return plants, startcapacity
end 

function marketprice(capacity, runningcosts, meritorder, slice, params)
    @unpack demand, availability, refprice, elasticity = params
    totalgeneration = 0.0
    price = Inf
    for order in meritorder
        if price < runningcosts[order]
            return price
        end
        totalgeneration += capacity[order] * availability[order, slice]
        price = refprice * (totalgeneration/demand[slice])^(1/elasticity)
        if price < runningcosts[order]
            return runningcosts[order]
        end
    end
    return price   # $/MWh
end

function annualprofit(capacity, runningcosts, meritorder, techindex, params)
    @unpack demand, availability, hoursperslice = params
    profit = 0.0
    for s = 1:length(demand)
        price = marketprice(capacity, runningcosts, meritorder, s, params)
        pricedelta = max(0, price - runningcosts[techindex])    # $/MWh
        profit += pricedelta * availability[techindex, s] * hoursperslice[s]  # $/MW investment
    end
    return profit/1000   # annual total profit expressed in $/kW investment
end

crf(r,T) = r / (1 - 1/(1+r)^T)

function profitability(capacity, runningcosts, meritorder, hurdlerate, params)
    @unpack plantsize, investcost, lifetime = params
    ntech = length(capacity)
    profitability = zeros(ntech)
    for i = 1:ntech
        capac = copy(capacity)
        capac[i] += plantsize
        profit = annualprofit(capac, runningcosts, meritorder, i, params)
        profitability[i] = profit/investcost[i] - crf(hurdlerate, lifetime[i])
    end
    return profitability    # relative profitability of each tech
end

function invest!(plants, year, capacity, runningcosts, meritorder, hurdlerates, params)
    @unpack tech, plantsize = params
    for hurdlerate in hurdlerates
        profits = profitability(capacity, runningcosts, meritorder, hurdlerate, params)
        maxprofit, t = findmax(profits)
        if maxprofit > 0
            push!(plants, Investment(tech[t], t, plantsize, year))
            capacity[t] += plantsize
            return true
        end
    end
    return false
end

carbontax(year) = clamp(2.5 * (year - 11), 0, 100)      # $/ton CO2
end_of_life(plant, lifetime, year) = (year == plant.year + lifetime[plant.techindex])

function simulate_all_years(numyears, params)
    @unpack techindex, varcost, emissionfactor, varcost_biogas, hurdlerates, lifetime = params
    plants, capacity = read_old_investments(params)
    capacities = zeros(numyears, length(capacity))
    gasindex = techindex["gas"]
    for year = 1:numyears
        capacities[year, :] = capacity
        tax = carbontax(year)
        runningcosts = varcost + tax * emissionfactor
        runningcosts[gasindex] = min(runningcosts[gasindex], varcost_biogas)
        meritorder = sortperm(runningcosts)
        shuffle!(hurdlerates)
        for plant in plants
            if end_of_life(plant, lifetime, year)
                capacity[plant.techindex] -= plant.capacity
                invest!(plants, year, capacity, runningcosts, meritorder, hurdlerates, params)
            end
        end
        # continue investing until nothing profitable
        while invest!(plants, year, capacity, runningcosts, meritorder, hurdlerates, params)
        end
        # capacities[year, :] = capacity    # I would rather set annual capacity here
    end
    return capacities, plants
end

# separate out the main loop since the function that assigns params is not type stable
function runmodel(numyears; args...)
    params = read_input_data(; args...)
    simulate_all_years(numyears, params)
end

end # module

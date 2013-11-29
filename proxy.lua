local convertValue do
	
	local getReturnValues = function(...)
		-- a hack to get the number of values
		-- can't just do #{...} because the table can be sparse
		-- e.g. #{nil,5,nil} --> 0
		return {n = select('#',...), ...}
	end
	
	local convertValues = function(mt, from, to, ...)
		local results = getReturnValues(...)
		for i = 1, results.n do
			results[i] = convertValue(mt,from,to,results[i])
		end
		return unpack(results,1,results.n)
	end

	convertValue = function(mt, from, to, value)
		-- if there is already a wrapper, return it
		-- no point in making a new one and it ensures consistency
		-- print(Game == Game) --> true
		local result = to.lookup[value]
		if result then
			return result
		end
		
		local type = type(value)
		if type == 'table' then
			result =  {}
			-- must be indexed before keys and values are converted
			-- otherwise stack overflow
			to.lookup[value] = result
			from.lookup[result] = value
			for key, value in pairs(value) do
				result[convertValue(mt,from,to,key)] = convertValue(mt,from,to,value)
			end
			if not from.trusted then
				-- any future changes by the user to the table
				-- will be picked up by the metatable and transferred to its partner
				setmetatable(value,mt)
			else
				setmetatable(result,mt)
			end
			return result
		elseif type == 'userdata' then
			-- create a userdata to serve as proxy for this one
			result = newproxy(true)
			local metatable = getmetatable(result)
			for event, metamethod in pairs(mt) do
				metatable[event] = metamethod
			end
			to.lookup[value] = result
			from.lookup[result] = value
			return result
		elseif type == 'function' then
			-- unwrap arguments, call function, wrap arguments
			result = function(...)
				local results = getReturnValues(ypcall(function(...) return value(...) end,convertValues(mt,to,from,...)))
				if results[1] then
					return convertValues(mt,from,to,unpack(results,2,results.n))
				else
					error(results[2],2)
				end
			end
			return result
		else
			-- numbers, strings, booleans, nil, and threads are left as-is
			-- because they are harmless
			return value
		end
	end
end

local proxy = {}

proxy.new = function(environment, hooks)
	hooks = hooks or {}
	
	-- allow wrappers to be garbage-collected
	local trusted = {trusted = true,lookup = setmetatable({},{__mode='k'})}
	local untrusted = {trusted = false,lookup = setmetatable({},{__mode='v'})}

	local metatable = {}
	for event, metamethod in pairs(hooks) do
		-- the metamethod will be fired on the wrapper class
		-- so we need to unwrap the arguments and wrap the return values
		metatable[event] = convertValue(metatable, trusted, untrusted, metamethod)
	end

	return convertValue(metatable, trusted, untrusted, environment)
end

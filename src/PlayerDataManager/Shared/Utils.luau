local module = {}

function module.getSignalNode<T>(pointer: T, path: { string | number }): T?
	for _, key in ipairs(path) do
		if not pointer[key] then
			return
		end

		pointer = pointer[key]
	end

	return pointer
end

function module.CreateSignalNode<T>(pointer: T, path: {string | number}): (T, string | number)
	for i = 1, #path - 1 do
		pointer = pointer[path[i]]
		if not pointer then
			pointer[path[i]] = {}
		end
	end

	return pointer, path[#path]
end

return module
#!../luajit

c = "abcd"

d = "abcde/fred"

function prefix_match(line, token, sep)
    if line:sub(1, #token) == token then
        local c = line:sub(#token+1, #token+1)
        if c == "" or c == sep then return true end
    end
    return false
end


if prefix_match(d, c, "/") then
	print("yes")
end

local lunajson = require("glb2convexshape.lunajson.lunajson")

local M = {}

local glb = {
    name = "",
    magic = "",
    version = 0,
    length = 0,
    chunk0length = 0,
    chunk0type = "",
    chunk0data = "",
    json = lunajson.decode("{}"),
    chunk1length = 0,
    chunk1type = "",
    chunk1data = "",
    bin = {}
}

-- 5120 - signed byte - 8
-- 5121 - unsigned byte - 8
-- 5122 - signed short - 16
-- 5123 - unsigned short - 16
-- 5125 - unsigned int - 32
-- 5126 - float - 32
local component_type = {
    [5120] = "s08",
    [5121] = "u08",
    [5122] = "s16",
    [5123] = "u16",
    [5125] = "u32",
    [5126] = "f32"
}

local accessors_type = {
    ["SCALAR"] = 1,
    ["VEC2"] = 2,
    ["VEC3"] = 3,
    ["VEC4"] = 4,
    ["MAT2"] = 4,
    ["MAT3"] = 9,
    ["MAT4"] = 16
}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
end

local function type_unpack(t, s, p)
    local num = {type = string.sub(t, 1, 1), value = 0, len = tonumber(string.sub(t, -2)) / 8, [1] = 0, [2] = 0, [3] = 0, [4] = 0}
    local num_float = {sign = 1, exponent = 0, fraction = 0, bias = 127, index = 0}
    for i = 1, num.len, 1 do
        num[i] = string.byte(s, p) or 0
        p = p + 1
    end

    for i = 1, num.len, 1 do
        if num.type == "u" or num.type == "s" then
            num.value = num.value + num[i] * (256 ^ (i - 1))
        elseif num.type == "f" then
            -- folat_num = sign * (2 ^ (exponent - bias)) * (1 + fraction)
            for j = 1, 8, 1 do
                -- this bit is 1
                if num[i] % 2 == 1 then 
                    if num_float.index < 23 then
                        num_float.fraction = num_float.fraction + 2 ^ (num_float.index - 23)
                    elseif num_float.index < 30 then 
                        num_float.exponent = num_float.exponent + 2 ^ (num_float.index - 23)
                    elseif num_float.index == 31 then 
                        num_float.sign = -1
                    end
                end
                num[i]  = math.modf(num[i] / 2)
                num_float.index = num_float.index + 1
            end
        end          
    end

    -- get negtive number
    if num.type == "s" then
        if num[num.len] >= 128 then
            num.value = num.value - (2 ^ tonumber(string.sub(t, -2)))
        end
    elseif num.type == "f" then
        if num_float.exponent == 0 and num_float.fraction == 0 then
            num.value = 0.0
        else
            num.value = num_float.sign * (2 ^ (num_float.exponent - num_float.bias)) * (1 + num_float.fraction)
        end
    end
    return num.value, p
end

local function str_unpack(s, p, l)
    if l <= 0 then
        return nil, p
    end
    return string.sub(s, p, p + l - 1), p + l
end

function M.generate_convexshape(glb_path)
    local pos = 1
    print("Generating convexshape file from "..glb_path:sub(2, -1)..".")
    glb.name = glb_path:sub(2, -5)
    local glb_file = read(glb_path:sub(2))
    
    -- check magic
    glb.magic, pos = str_unpack(glb_file, pos, 4)
    assert(glb.magic == "glTF", "Wrong file type!")
    
    -- check version
    glb.version, pos = type_unpack("u32", glb_file, pos)
    assert(glb.version == 2, "GLB version incompatibility!")

    --check length
    glb.length, pos = type_unpack("u32", glb_file, pos)
    -- print(glb.length, pos)
    -- print(string.len(glb_file))
    assert(glb.length == string.len(glb_file), "Incomplete file!")
    
    -- chunk 0 (JSON)
    glb.chunk0length, pos = type_unpack("u32", glb_file, pos)
    glb.chunk0type, pos = str_unpack(glb_file, pos, 4)
    --type check
    assert(glb.chunk0type == "JSON", "Chunk 0 type is not JSON") 
    glb.chunk0data, pos = str_unpack(glb_file, pos, glb.chunk0length)
    glb.json = lunajson.decode(glb.chunk0data)
    assert(string.sub(glb.json.asset.version, 1, 1) == "2", "json.asset.version not match")
    
    -- chunk 1 (BIN)
    glb.chunk1length, pos = type_unpack("u32", glb_file, pos)
    glb.chunk1type, pos = str_unpack(glb_file, pos, 4)
    if glb.chunk1length > 0 then
        assert(string.sub(glb.chunk1type, 1, 3) == "BIN", "Chunk 1 type is not BIN")
    end

    glb.chunk1data, _ = str_unpack(glb_file, pos, glb.chunk1length)
    -- print(glb.chunk1data)
    local line_num = 0
    -- get first "VEC3" data, which is vertex data
    for index, value in ipairs(glb.json.bufferViews) do
        glb.bin[index], _ = str_unpack(glb.chunk1data, (value.byteOffset or 0) + 1, value.byteLength)

        if glb.json.accessors[index].type == "VEC3" then
            local temp_pos = (glb.json.accessors[index].byteOffset or 0) + 1
            local temp_data = {} --make empyt
            --accessors offset
            local cvxshp_file = io.open(glb.name..".convexshape", "w+")
            io.output(cvxshp_file)
            io.write("shape_type: TYPE_HULL")
            for i = 1, glb.json.accessors[index].count, 1 do
                for j = 1, accessors_type[glb.json.accessors[index].type], 1 do
                    temp_data[j], temp_pos = type_unpack(component_type[glb.json.accessors[index].componentType], 
                    glb.bin[index], temp_pos)
                    if glb.json.accessors[index].max[j] ~= nil then
                        if temp_data[j] > glb.json.accessors[index].max[j] then
                            temp_data[j] = glb.json.accessors[index].max[j]
                        end
                    end

                    if glb.json.accessors[index].min[j] ~= nil then
                        if temp_data[j] < glb.json.accessors[index].min[j] then
                            temp_data[j] = glb.json.accessors[index].min[j]
                        end
                    end
                end
                line_num = line_num + 1
                -- print(tostring(line_num) .. ": (" .. table.concat(temp_data, ", ") .. "), ")
                io.write("\ndata: "..table.concat(temp_data, " data: "))
            end
            io.close(cvxshp_file)
            print("Generated "..glb.name..".convexshape.")
            break
        end
    end
end

return M
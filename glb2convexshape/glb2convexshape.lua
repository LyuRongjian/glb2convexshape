local lunajson = require("glb2convexshape.lunajson.lunajson")

local M = {}

local model_offset = 0.04

local glb = {
    path = "",
    namr = "",
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
    bin = {},
    vertex = {},
    indices = {},
    unit_normal_vector = {}
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

function print_r ( t )  
    local print_r_cache={}
    local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            print(indent.."*"..tostring(t))
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                for pos,val in pairs(t) do
                    if (type(val)=="table") then
                        print(indent.."["..pos.."] => "..tostring(t).." {")
                        sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                        print(indent..string.rep(" ",string.len(pos)+6).."}")
                    elseif (type(val)=="string") then
                        print(indent.."["..pos..'] => "'..val..'"')
                    else
                        print(indent.."["..pos.."] => "..tostring(val))
                    end
                end
            else
                print(indent..tostring(t))
            end
        end
    end
    if (type(t)=="table") then
        print(tostring(t).." {")
        sub_print_r(t,"  ")
        print("}")
    else
        sub_print_r(t,"  ")
    end
    print()
end


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
    glb.path = glb_path:sub(2, -5)
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
    -- print(glb.chunk0data)
    glb.json = lunajson.decode(glb.chunk0data)
    assert(string.sub(glb.json.asset.version, 1, 1) == "2", "json.asset.version not match")
    
    -- chunk 1 (BIN)
    glb.chunk1length, pos = type_unpack("u32", glb_file, pos)
    glb.chunk1type, pos = str_unpack(glb_file, pos, 4)
    if glb.chunk1length > 0 then
        assert(string.sub(glb.chunk1type, 1, 3) == "BIN", "Chunk 1 type is not BIN")
    end

    glb.chunk1data, _ = str_unpack(glb_file, pos, glb.chunk1length)
    local vertex_num = 0
    assert(type(glb.json.meshes[1].primitives[1].attributes.POSITION) == "number", "Position data lost!")
    local postion_index = glb.json.meshes[1].primitives[1].attributes.POSITION + 1
    
    assert(type(glb.json.meshes[1].primitives[1].indices) == "number", "Indices data lost!")
    local indices_index = glb.json.meshes[1].primitives[1].indices + 1
    
    local mesh_mode = glb.json.meshes[1].primitives[1].model
    assert(mesh_mode == nil or mesh_mode == 4 or mesh_mode == 5 or mesh_mode == 6, "Mesh mode not support!")

    assert(type(glb.json.meshes[1].primitives[1].attributes.NORMAL) == "number", "Normal data lost!")
    local normal_index = glb.json.meshes[1].primitives[1].attributes.NORMAL + 1 
    print("NORMAL:"..tostring(normal_index))
    assert(type(glb.json.meshes[1].primitives[1].attributes.TANGENT) == "number", "Tangent data lost!")
    local tangent_index = glb.json.meshes[1].primitives[1].attributes.TANGENT + 1 
    print("TANGENT:"..tostring(tangent_index))
    
    for index, value in ipairs(glb.json.bufferViews) do
        if index == postion_index 
        or index == indices_index 
        or index == normal_index 
        then
            -- get data
            glb.bin[index], _ = str_unpack(glb.chunk1data, (value.byteOffset or 0) + 1, value.byteLength)

            local temp_pos = (glb.json.accessors[index].byteOffset or 0) + 1
            local temp_data = {} --empty
            
            --accessors offset
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
                
                if index == postion_index then
                    glb.vertex[i] = {}
                    for idx, val in ipairs(temp_data) do
                        glb.vertex[i][idx] = val
                    end 
                    -- print(tostring(i)..": "..table.concat(glb.vertex[i], ","))
                    -- print("temp:"..table.concat(temp_data, ","))
                elseif index == indices_index then
                    glb.indices[i] = temp_data[1]
                    -- print(tostring(i).."~"..tostring(glb.indices[i])..",")
                elseif index == normal_index then
                    -- print("( "..table.concat(temp_data, ", ").." )\n")
                    glb.unit_normal_vector[i] = {}
                    for idx, val in ipairs(temp_data) do
                        glb.unit_normal_vector[i][idx] = -val     
                    end
                    -- local mold_len = 0
                    -- for _, v in ipairs(temp_data) do
                    --     mold_len = (v ^ 2) + mold_len
                    -- end
                    -- mold_len = math.sqrt(mold_len)
                    -- glb.unit_normal_vector[i] = {}
                    -- -- get inverse vector
                    -- for p, v in ipairs(temp_data) do
                    --     glb.unit_normal_vector[i][p] = -v/mold_len
                    -- end
                end
            end
        end
    end

    -- for index, value in ipairs(glb.vertex) do
    --     for idx, val in ipairs(value) do
    --         glb.vertex[index][idx] = val + (model_offset * glb.unit_normal_vector[index][idx])
    --     end
    -- end
    
    local slash_pos_before_name = string.find(string.reverse(glb.path), '/')
    
    glb.name = string.sub(glb.path, -slash_pos_before_name)
    local cvxshp_file 
    local file_num = 0

    for index, value in ipairs(glb.indices) do
        -- Each consecutive set of three vertices defines a single triangle primitive
        if mesh_mode == nil or mesh_mode == 4 then
            if (index - 1) % 3 == 0 then
                file_num  = file_num + 1
                if index > 1 then
                    io.close(cvxshp_file)
                end
                print("Generated "..glb.path.."-convexshapes"..glb.name..'-'..tostring(file_num)..".convexshape")
                cvxshp_file = io.open(glb.path.."-convexshapes"..glb.name..'-'..tostring(file_num)..".convexshape", "w+")
                io.output(cvxshp_file)
                io.write("shape_type: TYPE_HULL")
            end
            io.write("\ndata: "..table.concat(glb.vertex[value + 1], " data: "))
        -- One triangle primitive is defined by each vertex and the two vertices that follow it    
        elseif mesh_mode == 5 then 
            if glb.indices[index + 1] ~= nil and glb.indices[index + 2] ~= nil then
                file_num  = file_num + 1
                if index > 1 then
                    io.close(cvxshp_file)
                end                
                print("Generated "..glb.path.."-convexshapes"..glb.name..'-'..tostring(file_num)..".convexshape")
                cvxshp_file = io.open(glb.path.."-convexshapes"..glb.name..'-'..tostring(file_num)..".convexshape", "w+")
                io.output(cvxshp_file)
                io.write("shape_type: TYPE_HULL")
                io.write("\ndata: "..table.concat(glb.vertex[glb.indices[index] + 1], " data: "))
                io.write("\ndata: "..table.concat(glb.vertex[glb.indices[index + 1] + 1], " data: "))
                io.write("\ndata: "..table.concat(glb.vertex[glb.indices[index + 2] + 1], " data: "))
            end
        -- Triangle primitives are defined around a shared common vertex
        elseif mesh_mode == 6 then
            if index > 1 and glb.indices[index + 1] ~= nil then
                file_num  = file_num + 1
                if index > 2 then
                    io.close(cvxshp_file)
                end
                print("Generated "..glb.path.."-convexshapes"..glb.name..'-'..tostring(file_num)..".convexshape")
                cvxshp_file = io.open(glb.path.."-convexshapes"..glb.name..'-'..tostring(file_num)..".convexshape", "w+")
                io.output(cvxshp_file)
                io.write("shape_type: TYPE_HULL")
                io.write("\ndata: "..table.concat(glb.vertex[glb.indices[index] + 1], " data: "))
                io.write("\ndata: "..table.concat(glb.vertex[glb.indices[index + 1] + 1], " data: "))
                io.write("\ndata: "..table.concat(glb.vertex[glb.indices[1] + 1], " data: "))          
            end
        end
    end
    io.close(cvxshp_file)

    local go_file = io.open(glb.path.."-collision.go", "w+")
    io.output(go_file)

    for i = 1, file_num do
        io.write("embedded_components {\n")
        io.write("  id: \"collisionobject".."-"..tostring(i).."\"\n")
        io.write("  type: \"collisionobject\"\n")
        io.write("  data: \"collision_shape: \\\""..glb_path:sub(1, -5).."-convexshapes"..glb.name..'-'..tostring(i)..".convexshape".."\\\"\\n\"\n")
        io.write("  \"type: COLLISION_OBJECT_TYPE_STATIC\\n\"\n")
        io.write("  \"mass: 0.0\\n\"\n")
        io.write("  \"friction: 0.1\\n\"\n")
        io.write("  \"restitution: 0.5\\n\"\n")
        io.write("  \"group: \\\"world\\\"\\n\"\n")
        io.write("  \"mask: \\\"world, marbles\\\"\\n\"\n")
        io.write("  \"linear_damping: 0.0\\n\"\n")
        io.write("  \"angular_damping: 0.0\\n\"\n")
        io.write("  \"locked_rotation: false\\n\"\n")
        io.write("  \"bullet: false\\n\"\n")
        io.write("  \"\"\n")
        io.write("  position {\n")
        io.write("    x: 0.0\n")
        io.write("    y: 0.0\n")
        io.write("    z: 0.0\n")
        io.write("  }\n")
        io.write("  rotation {\n")
        io.write("    x: 0.0\n")
        io.write("    y: 0.0\n")
        io.write("    z: 0.0\n")
        io.write("    w: 1.0\n")
        io.write("  }\n")
        io.write("}\n")
    end
    io.close(go_file)
end

return M

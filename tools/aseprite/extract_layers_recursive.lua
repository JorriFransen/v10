local sprite = app.activeSprite
if not sprite then
    return app.alert("No active sprite")
end

local out_dir = app.params["out_dir"]

local function recursiveExport(name_prefix, layer)
    if layer.isGroup then
        for _,l in ipairs(layer.layers) do
            recursiveExport(name_prefix .. layer.name .. "_", l)
        end
    else

        local filename = app.fs.joinPath(out_dir, name_prefix .. layer.name .. ".bmp")

        local old_layer_name = layer.name;
        layer.name = name_prefix .. layer.name;

        app.command.ExportSpriteSheet{
            ui = false,
            textureFilename = filename,
            layer = layer.name,
            splitLayers = true,

        }

        layer.name = old_layer_name;
    end
end

local in_filename = app.fs.fileName(sprite.filename)
local in_ext = app.fs.fileExtension(sprite.filename)
local name_prefix = string.sub(in_filename, 1 ,-(#in_ext + 2)) .. "_"


for _,layer in ipairs(sprite.layers) do
    recursiveExport(name_prefix, layer)
end



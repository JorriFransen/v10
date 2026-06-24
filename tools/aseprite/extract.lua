local sprite = app.activeSprite
if not sprite then
    return app.alert("No active sprite")
end

local out_dir = app.fs.joinPath(app.fs.filePath(sprite.filename), "test")
if out_dir == "" then
    out_dir = app.fs.currentPath
end

local in_filename = app.fs.fileName(sprite.filename)
local in_ext = app.fs.fileExtension(sprite.filename)
local filename = string.sub(in_filename, 1 ,-(#in_ext + 2))
local filepath = app.fs.joinPath(out_dir, filename .. ".bmp")

app.command.ExportSpriteSheet{
    ui = false,
    textureFilename = filepath,
}


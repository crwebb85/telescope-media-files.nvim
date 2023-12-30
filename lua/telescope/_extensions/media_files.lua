local has_telescope, _ = pcall(require, "telescope")

-- TODO: make dependency errors occur in a better way
if not has_telescope then
	error("This plugin requires telescope.nvim (https://github.com/nvim-telescope/telescope.nvim)")
end

local utils = require("telescope.utils")
local defaulter = utils.make_default_callable
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values

local M = {}

local filetypes = {}
local find_cmd = ""

---Get file extension from path
---@param url string file path or url
---@return string
local function get_file_extension(url)
	local extension_match = url:match("^.+(%..+)$")
	if type(extension_match) == "string" then
		local extension, _ = string.gsub(extension_match, "%.", "")
		return extension
	else
		return ""
	end
end

---@class PreviewDrawerOptions
---@field path string
---@field preview_col number
---@field preview_line number
---@field preview_width number
---@field preview_height number

local function get_render_at_size_command(path, width, height)
	return {
		"chafa",
		path,
		"--format=symbols",
		"--clear",
		"--animate=off",
		"--center=on",
		"--clear",
		"--size",
		string.format("%sx%s", width, height),
	}
end

---@param opts PreviewDrawerOptions
local function image_preview(opts)
	return get_render_at_size_command(opts.path, opts.preview_width, opts.preview_height)
end

---@param opts PreviewDrawerOptions
local function gif_preview(opts)
	return get_render_at_size_command(opts.path, opts.preview_width, opts.preview_height)
end

---@param opts PreviewDrawerOptions
local function video_preview(opts)
	-- TODO
	error("unimplemented preview")
	-- if ! command -v viu &> /dev/null; then
	--   echo "ffmpegthumbnailer could not be found in your path,\nplease install it to display video previews"
	--   exit
	-- fi
	-- path="${2##*/}"
	-- echo -e "Loading preview..\nFile: $path"
	-- ffmpegthumbnailer -i "$2" -o "${TMP_FOLDER}/${path}.png" -s 0 -q 10
	-- clear
	-- render_at_size "${5}" "${6}" "${TMP_FOLDER}/${path}.png" "${7}"

	-- return get_render_at_size_command(opts.path, opts.preview_width, opts.preview_height)
end

---@param opts PreviewDrawerOptions
local function pdf_preview(opts)
	error("unimplemented preview")
	-- path="${2##*/}"
	--   echo -e "Loading preview..\nFile: $path"
	--   [[ ! -f "${TMP_FOLDER}/${path}.png" ]] && pdftoppm -png -singlefile "$2" "${TMP_FOLDER}/${path}.png"
	--   clear
	--   render_at_size "${5}" "${6}" "${TMP_FOLDER}/${path}.png" "${7}"

	-- return get_render_at_size_command(opts.path, opts.preview_width, opts.preview_height)
end

local draw_matcher = {
	["jpg"] = image_preview,
	["png"] = image_preview,
	["jpeg"] = image_preview,
	["webp"] = image_preview,
	["svg"] = image_preview,
	["gif"] = gif_preview,
	["avi"] = video_preview,
	["mp4"] = video_preview,
	["wmv"] = video_preview,
	["dat"] = video_preview,
	["3gp"] = video_preview,
	["ogv"] = video_preview,
	["mkv"] = video_preview,
	["mpg"] = video_preview,
	["mpeg"] = video_preview,
	["vob"] = video_preview,
	["m2v"] = video_preview,
	["mov"] = video_preview,
	["webm"] = video_preview,
	["mts"] = video_preview,
	["m4v"] = video_preview,
	["rm"] = video_preview,
	["qt"] = video_preview,
	["divx"] = video_preview,
	["pdf"] = pdf_preview,
	["epub"] = pdf_preview,
}

M.base_directory = ""
M.media_preview = defaulter(function(opts)
	return previewers.new_termopen_previewer({
		get_command = opts.get_command or function(entry, _)
			local tmp_table = vim.split(entry.value, "\t")
			local preview = opts.get_preview_window()

			opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()

			if vim.tbl_isempty(tmp_table) then
				return { "echo", "" }
			end

			local path = string.format([[%s/%s]], opts.cwd, tmp_table[1])
			local extension = get_file_extension(path)

			local preview_drawer = draw_matcher[extension]
			if preview_drawer then
				return preview_drawer({
					path = path,
					preview_col = preview.col,
					preview_line = preview.line + 1,
					preview_width = preview.width,
					preview_height = preview.height,
				})
			else
				error("invalid file type", 2)
			end
		end,
	})
end, {})

function M.media_files(opts)
	local find_commands = {
		find = {
			"find",
			".",
			"-iregex",
			[[.*\.\(]] .. table.concat(filetypes, "\\|") .. [[\)$]],
		},
		fd = {
			"fd",
			"--type",
			"f",
			"--regex",
			[[.*.(]] .. table.concat(filetypes, "|") .. [[)$]],
			".",
		},
		fdfind = {
			"fdfind",
			"--type",
			"f",
			"--regex",
			[[.*.(]] .. table.concat(filetypes, "|") .. [[)$]],
			".",
		},
		rg = {
			"rg",
			"--files",
			"--glob",
			[[*.{]] .. table.concat(filetypes, ",") .. [[}]],
			".",
		},
	}

	if not vim.fn.executable(find_cmd) then
		error("You don't have " .. find_cmd .. "! Install it first or use other finder.")
		return
	end

	if not find_commands[find_cmd] then
		error(find_cmd .. " is not supported!")
		return
	end

	local sourced_file = require("plenary.debug_utils").sourced_filepath()
	M.base_directory = vim.fn.fnamemodify(sourced_file, ":h:h:h:h")
	opts = opts or {}
	opts.attach_mappings = function(prompt_bufnr, map)
		actions.select_default:replace(function()
			local entry = action_state.get_selected_entry()
			actions.close(prompt_bufnr)
			if entry[1] then
				local filename = entry[1]
				vim.fn.setreg(vim.v.register, filename)
				vim.notify("The image path has been copied!")
			end
		end)
		return true
	end
	opts.path_display = { "shorten" }

	local popup_opts = {}
	opts.get_preview_window = function()
		return popup_opts.preview
	end
	local picker = pickers.new(opts, {
		prompt_title = "Media Files",
		finder = finders.new_oneshot_job(find_commands[find_cmd], opts),
		previewer = M.media_preview.new(opts),
		sorter = conf.file_sorter(opts),
	})

	local line_count = vim.o.lines - vim.o.cmdheight
	if vim.o.laststatus ~= 0 then
		line_count = line_count - 1
	end
	popup_opts = picker:get_window_options(vim.o.columns, line_count)
	picker:find()
end

return require("telescope").register_extension({
	setup = function(ext_config)
		filetypes = ext_config.filetypes or { "png", "jpg", "gif", "mp4", "webm", "pdf" }
		find_cmd = ext_config.find_cmd or "fd"
	end,
	exports = {
		media_files = M.media_files,
	},
})

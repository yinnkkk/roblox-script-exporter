-- One-way Roblox script exporter plugin.
-- Scans DataModel scripts and sends one JSON payload to localhost.

local HttpService = game:GetService("HttpService")

local BASE_URL = "http://127.0.0.1:34873"
local EXPORT_URL = BASE_URL .. "/export"
local MANIFEST_URL = BASE_URL .. "/manifest"
local FILE_URL = BASE_URL .. "/file"
local FIXED_PROJECT_ROOT = "MyGame"

local SCRIPT_TYPES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
}

local toolbar = plugin:CreateToolbar("Roblox Exporter")
local export_button = toolbar:CreateButton(
	"Export Scripts",
	"Export all Script/LocalScript/ModuleScript instances to localhost",
	""
)
local import_button = toolbar:CreateButton(
	"Import Scripts",
	"Import scripts from disk and overwrite matching instances in Studio",
	""
)

local function get_top_level_service(instance: Instance): Instance?
	local current = instance
	while current and current.Parent and current.Parent ~= game do
		current = current.Parent
	end

	if current and current.Parent == game then
		return current
	end

	return nil
end

local function get_relative_path(service: Instance, script_instance: Instance): {string}?
	local parts = {}
	local cursor = script_instance.Parent

	while cursor and cursor ~= service do
		table.insert(parts, 1, cursor.Name)
		cursor = cursor.Parent
	end

	if cursor ~= service then
		return nil
	end

	return parts
end

local function collect_scripts(): {{[string]: any}}
	local collected = {}

	for _, instance in ipairs(game:GetDescendants()) do
		if SCRIPT_TYPES[instance.ClassName] then
			local service = get_top_level_service(instance)
			if service then
				local relative_path = get_relative_path(service, instance)
				if relative_path then
					local ok, source_or_error = pcall(function()
						return (instance :: any).Source
					end)

					local source = ""
					if ok then
						source = source_or_error
					else
						warn(
							("[RobloxExporter] Could not read Source for %s: %s"):format(
								instance:GetFullName(),
								tostring(source_or_error)
							)
						)
					end

					table.insert(collected, {
						service = service.Name,
						path = relative_path,
						name = instance.Name,
						type = instance.ClassName,
						source = source,
					})
				end
			end
		end
	end

	-- Deterministic ordering keeps exports stable across runs.
	table.sort(collected, function(a, b)
		if a.service ~= b.service then
			return a.service < b.service
		end

		local a_path = table.concat(a.path, "/")
		local b_path = table.concat(b.path, "/")
		if a_path ~= b_path then
			return a_path < b_path
		end

		if a.name ~= b.name then
			return a.name < b.name
		end

		return a.type < b.type
	end)

	return collected
end

local function run_export()
	local scripts = collect_scripts()
	local payload = {
		-- Fixed destination root ensures every export refreshes the same folder.
		projectRoot = FIXED_PROJECT_ROOT,
		scripts = scripts,
	}

	local body = HttpService:JSONEncode(payload)
	local ok, response_or_error = pcall(function()
		return HttpService:PostAsync(
			EXPORT_URL,
			body,
			Enum.HttpContentType.ApplicationJson
		)
	end)

	if ok then
		print(("[RobloxExporter] Export complete. Sent %d scripts."):format(#scripts))
		print(("[RobloxExporter] Server response: %s"):format(tostring(response_or_error)))
	else
		warn("[RobloxExporter] Export failed: " .. tostring(response_or_error))
		warn("[RobloxExporter] Make sure export_server.py is running on 127.0.0.1:34873.")
	end
end

local function http_get_json(url: string)
	local ok, result = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if not ok then
		return nil, "HTTP request failed: " .. tostring(result)
	end

	local ok_decode, data_or_error = pcall(function()
		return HttpService:JSONDecode(result)
	end)

	if not ok_decode then
		return nil, "Failed to decode JSON: " .. tostring(data_or_error)
	end

	return data_or_error, nil
end

local function http_get_file(rel_file: string)
	local url = FILE_URL
		.. "?projectRoot=" .. HttpService:UrlEncode(FIXED_PROJECT_ROOT)
		.. "&relFile=" .. HttpService:UrlEncode(rel_file)
	local data, err = http_get_json(url)
	if not data then
		return nil, err
	end
	return data.source, nil
end

local function find_target_instance(entry)
	local service = game:FindFirstChild(entry.service)
	if not service then
		return nil, "missing service"
	end

	local current = service
	for _, part in ipairs(entry.path or {}) do
		local child = current:FindFirstChild(part)
		if not child then
			return nil, "missing folder path"
		end
		current = child
	end

	local target = current:FindFirstChild(entry.name)
	if not target then
		return nil, "missing script"
	end
	if target.ClassName ~= entry.type then
		return nil, "type mismatch"
	end
	return target, nil
end

local function run_import()
	local manifest_url = MANIFEST_URL .. "?projectRoot=" .. HttpService:UrlEncode(FIXED_PROJECT_ROOT)
	local manifest, err = http_get_json(manifest_url)
	if not manifest then
		warn("[RobloxExporter] Import failed: " .. err)
		warn("[RobloxExporter] Make sure export_server.py is running on 127.0.0.1:34873.")
		return
	end

	local files = manifest
	if type(manifest) == "table" and manifest.files then
		files = manifest.files
	end
	if type(files) ~= "table" then
		warn("[RobloxExporter] Import failed: malformed manifest response.")
		return
	end

	local total = #files
	local imported = 0
	local skipped = 0
	local reasons = {}
	local skipped_examples = {}

	for _, entry in ipairs(files) do
		local target, reason = find_target_instance(entry)
		if not target then
			skipped += 1
			reasons[reason] = (reasons[reason] or 0) + 1
			if not skipped_examples[reason] then
				skipped_examples[reason] = {}
			end
			local example = string.format("%s/%s/%s",
				entry.service or "?",
				table.concat(entry.path or {}, "/"),
				entry.name or "?"
			)
			table.insert(skipped_examples[reason], example)
			continue
		end

		local source, file_err = http_get_file(entry.relFile)
		if not source then
			skipped += 1
			reasons["file read failed"] = (reasons["file read failed"] or 0) + 1
			if not skipped_examples["file read failed"] then
				skipped_examples["file read failed"] = {}
			end
			table.insert(skipped_examples["file read failed"], entry.relFile or "?")
			continue
		end

		local ok, set_err = pcall(function()
			(target :: any).Source = source
		end)

		if ok then
			imported += 1
		else
			skipped += 1
			reasons["source set failed"] = (reasons["source set failed"] or 0) + 1
			if not skipped_examples["source set failed"] then
				skipped_examples["source set failed"] = {}
			end
			table.insert(skipped_examples["source set failed"], target:GetFullName())
			warn(("[RobloxExporter] Failed to set Source for %s: %s"):format(
				target:GetFullName(),
				tostring(set_err)
			))
		end
	end

	print(("[RobloxExporter] Import complete. Total=%d Imported=%d Skipped=%d"):format(
		total,
		imported,
		skipped
	))

	local reason_list = {}
	for reason, count in pairs(reasons) do
		table.insert(reason_list, { reason = reason, count = count })
	end

	table.sort(reason_list, function(a, b)
		return a.count > b.count
	end)

	local max_reasons = math.min(10, #reason_list)
	for i = 1, max_reasons do
		local item = reason_list[i]
		print(("[RobloxExporter] Skipped: %s (%d)"):format(item.reason, item.count))
		local examples = skipped_examples[item.reason]
		if examples and #examples > 0 then
			local limit = math.min(3, #examples)
			for j = 1, limit do
				print(("[RobloxExporter]   • %s"):format(examples[j]))
			end
		end
	end
end

export_button.Click:Connect(run_export)
import_button.Click:Connect(run_import)

-- One-way Roblox script exporter plugin.
-- Scans DataModel scripts and sends one JSON payload to localhost.

local HttpService = game:GetService("HttpService")

local EXPORT_URL = "http://127.0.0.1:34873/export"
local FIXED_PROJECT_ROOT = "MyGame"

local SCRIPT_TYPES = {
	Script = true,
	LocalScript = true,
	ModuleScript = true,
}

local toolbar = plugin:CreateToolbar("Roblox Exporter")
local button = toolbar:CreateButton(
	"Export Scripts",
	"Export all Script/LocalScript/ModuleScript instances to localhost",
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

button.Click:Connect(run_export)

local WorldBuilder = require(__proxy("Server/World/WorldBuilder"))
WorldBuilder.build()
for _, line in ipairs(DUMP(workspace, "world")) do
	print(line)
end

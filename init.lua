local mq = require('mq')
local ImGui = require('ImGui')

local App = require('asyst.App')

local app = App.new(mq, ImGui)

mq.imgui.init('AsystUI', function()
  app:DrawUI()
end)

app:Initialize()
app:Run()
app:Shutdown()
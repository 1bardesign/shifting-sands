local ui = require("partner.partner")

return function(w, h)
	local container = ui.container:new()

	local font_heading = lg.newFont(20)
	local font_body = lg.newFont(14)

	local welcome_width = 300
	local welcome_tray
	welcome_tray = ui.tray:new(w * 0.5, h * 0.5, welcome_width, 84):add_children({
		ui.text:new(font_heading, "Shifting Sands", welcome_width, "center"),
		ui.text:new(font_body, table.concat({
			"I built this little island generator for #procjam 2019",
			"It does the majority of its work on the gpu, but i've tried to make sure"..
			" that it will run ok on a modern integrated card.",
			"Please let me know if you have any trouble on twitter or github",
			"Enjoy!",
		}, "\n\n"), welcome_width, "left"),
		ui.text:new(font_body, "~Max", welcome_width, "right"),
		ui.button:new("(close welcome)", welcome_width + 20, 32, function()
			container:remove_child(welcome_tray)
		end),
	}):set_anchor("center", "center")

	local button_tray = ui.tray:new(w * 0.5, h - 10, 400, 84):add_children({
		ui.row:new():add_children({
			ui.button:new("regen", 100, 32, love.load),
			ui.button:new("quit", 100, 32, function()
				love.event.quit()
			end),
		})
	}):set_anchor("center", "bottom")

	local screenshot_tray = ui.tray:new(w - 10, h - 10, 400, 84):add_children({
		ui.text:new(font_body, "screenshot", 80, "center"),
		ui.button:new("take", 100, 32, function()
			local id = sbc:newImageData()
			love.filesystem.write(
				string.format("screenshot-%d.png", os.time()),
				id:encode("png")
			)
		end),
		ui.button:new("browse", 100, 32, function()
			love.system.openURL("file://"..love.filesystem.getSaveDirectory())
		end),
	}):set_anchor("right", "bottom")

	local link_tray = ui.tray:new(10, h - 10, 400, 84):add_children({
		ui.text:new(font_body, "links", 80, "center"),
		ui.button:new("twitter", 100, 32, function()
			love.system.openURL("https://twitter.com/1bardesign")
		end),
		ui.button:new("github", 100, 32, function()
			love.system.openURL("https://github.com/1bardesign/procjam-2019")
		end),
	}):set_anchor("left", "bottom")

	local hide_tray = ui.tray:new(10, 10, 400, 84):add_children({
		ui.button:new("hide ui", 100, 32, function()
			hide_ui = true
		end),
	}):set_anchor("left", "top")

	container:add_children({
		welcome_tray,
		button_tray,
		screenshot_tray,
		link_tray,
		hide_tray,
	})

	function container:update(dt)
		self:layout()
	end

	function container:resize(w, h)
		--anything to do?
		self:layout()
	end

	--get everything up to date
	container:update(0)

	return container
end
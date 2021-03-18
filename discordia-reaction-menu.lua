local discordia = require("discordia")
local timer = require("timer")
discordia.extensions()

local rm = {}

rm.reactions = {
	exit = "🛑",
	back = "⬅",
	choices = {
		"1️⃣",
		"2️⃣",
		"3️⃣",
		"4️⃣",
		"5️⃣",
		"6️⃣",
		"7️⃣",
		"8️⃣",
		"9️⃣"
	}
}

rm.validReactions = {["🛑"]=true, ["⬅"]=true, ["1️⃣"]=true, ["2️⃣"]=true, ["3️⃣"]=true, ["4️⃣"]=true, ["5️⃣"]=true, ["6️⃣"]=true, ["7️⃣"]=true, ["8️⃣"]=true, ["9️⃣"]=true}

rm.choiceReactions = {["1️⃣"]=1, ["2️⃣"]=2, ["3️⃣"]=3, ["4️⃣"]=4, ["5️⃣"]=5, ["6️⃣"]=6, ["7️⃣"]=7, ["8️⃣"]=8, ["9️⃣"]=9}

-- Like Emitter:waitFor, but waits for either of two events
-- If there is a timeout and it's reached, returns false; otherwise returns the name of the event that was emitted
local waitForAny = function(emitter, nameA, nameB, timeout, predicateA, predicateB)
	local thread = coroutine.running()
	local fnA, fnB

	fnA = emitter:onSync(nameA, function(...)
		if predicateA and not predicateA(...) then return end
		if timeout then
			timer.clearTimeout(timeout)
		end
		emitter:removeListener(nameA, fnA)
		emitter:removeListener(nameB, fnB)
		return assert(coroutine.resume(thread, nameA, ...))
	end)

	fnB = emitter:onSync(nameB, function(...)
		if predicateB and not predicateB(...) then return end
		if timeout then
			timer.clearTimeout(timeout)
		end
		emitter:removeListener(nameA, fnA)
		emitter:removeListener(nameB, fnB)
		return assert(coroutine.resume(thread, nameB, ...))
	end)

	timeout = timeout and timer.setTimeout(timeout, function()
		emitter:removeListener(nameA, fnA)
		emitter:removeListener(nameB, fnB)
		return assert(coroutine.resume(thread, false))
	end)

	return coroutine.yield()
end

local exit = function(message)
	message:clearReactions()
	message:setEmbed{
		title = "Done!",
		description = "You've chosen to exit this menu.",
		color = discordia.Color.fromHex("00ff00").value
	}
end

local timeout = function(message)
	message:clearReactions()
	message:setEmbed{
		title = "Timed out!",
		description = "You haven't used this menu for a while, so it has now closed.",
		color = discordia.Color.fromHex("ff0000").value
	}
end

-- returns the next page to go to
local showPage = function(message, author, menu, data, page, isFirstPage)
	local embed = {
		title = page.title,
		color = discordia.Color.fromHex(page.color).value,
		footer = {text="User: "..author.tag.."  |  Menu will close:"},
		timestamp = discordia.Date.fromSeconds(os.time()+math.floor(menu.timeout/1000)):toISO("T", "Z")
	}

	if page.getTitle then
		embed.title = page:getTitle(menu, data)
	elseif page.title then
		embed.title = page.title
	end

	local choices = page.getChoices and page:getChoices(menu, data) or page.choices

	local description = {}
	if page.getDescription then
		table.insert(description, page:getDescription(menu, data).."\n")
	elseif page.description then
		table.insert(description, page.description.."\n")
	end
	if not isFirstPage then table.insert(description, rm.reactions.back.." Back") end
	table.insert(description, rm.reactions.exit.." Exit")
	if choices then
		table.insert(description, "")
		for num, choice in ipairs(choices) do
			table.insert(description, rm.reactions.choices[num].." "..choice.name..(choice.getValue and " *("..choice:getValue(menu, data)..")*" or ""))
		end
	end
	embed.description = table.concat(description, "\n")

	message:setEmbed(embed)

	local eventName, object1, object2

	while true do
		if page.onPrompt then
			eventName, object1, object2 = waitForAny(message.client, "messageCreate", "reactionAdd", menu.timeout, 
				function(m) return m.author.id==author.id and m.channel.id==message.channel.id end,
				function(r, a) return r.message.id==message.id and a~=r.client.user.id end)
		else
			local success
			success, object1, object2 = message.client:waitFor("reactionAdd", menu.timeout, 
				function(r, a) return r.message.id==message.id and a~=r.client.user.id end)
			eventName = success and "reactionAdd" or false
		end

		if not eventName then
			menu._isClosed = true
			timeout(message)
			return false
		elseif eventName=="messageCreate" then
			local nextPage = page:onPrompt(menu, data, object1) -- run onPrompt first because runtime can vary, looks better
			timer.setTimeout(150, coroutine.wrap(object1.delete), object1) -- wait 150 ms to delete the user's message so it gets deleted after the page update, looks better
			return nextPage
		elseif eventName=="reactionAdd" then
			object1:delete(object2) -- delete their reaction
			if object2==author.id and rm.validReactions[object1.emojiName] then
				if object1.emojiName==rm.reactions.exit then
					menu._isClosed = true
					exit(message)
					return false
				elseif object1.emojiName==rm.reactions.back and not isFirstPage then
					return page.onBack and page:onBack(menu, data) or true
				elseif choices and rm.choiceReactions[object1.emojiName] then
					local num = rm.choiceReactions[object1.emojiName]
					if choices[num] then
						return choices[num].onChoose and choices[num]:onChoose(menu, data) or choices[num].destination
					end
				end
			end
		end
	end
end

-- validation functions
rm.Menu = function(menu)
	assert(menu.startPage, "menu.startPage must be provided")
	if menu.timeout then
		assert(type(menu.timeout)=="number" and menu.timeout>=1000, "menu.timeout must be a number at least 1000 (milliseconds)")
	else
		menu.timeout = 120000
	end
	menu.storage = menu.storage or {}
	menu.type = "Menu"
	return menu
end

rm.Page = function(page)
	assert(not (page.choices and page.getChoices), "page.choices or page.getChoices may be provided, but not both")
	assert(not (page.title and page.getTitle), "page.title or page.getTitle may be provided, but not both")
	assert(not (page.description and page.getDescription), "page.description or page.getDescription may be provided, but not both")
	if page.choices then
		assert(type(page.choices)=="table" and #page.choices<=9, "page.choices must be a table containing at most 9 Choice objects")
	end
	if page.onPrompt then
		assert(type(page.onPrompt)=="function", "page.onPrompt must be a function if provided")
	end
	if page.inHistory==nil then
		if page.onPrompt then
			page.inHistory = false
		else
			page.inHistory = true
		end
	end
	page.color = page.color or "00ff00"
	assert(type(page.color)=="string" and #page.color==6, "page.color must be a 6 digit hex number")
	page.type = "Page"
	return page
end

rm.Choice = function(choice)
	assert(choice.name, "choice.name must be provided")
	assert((choice.destination or choice.onChoose) and not (choice.destination and choice.onChoose), "exactly one of choice.destination or choice.onChoose must be provided")
	if choice.getValue then
		assert(type(choice.getValue)=="function", "choice.getValue must be a function")
	end
	choice.type = "Choice"
	return choice
end

-- pagination functions

-- splits choices into individual pages preemptively
-- fast to display, but editing after pagination is very difficult
-- NOT FINISHED!!!
-- rm.paginateChoices = function(choices, title, description)
-- 	local pages
-- 	local onBack = function(self, menu, data)
-- 		-- back button should go back to the page before the first paginated page
-- 		-- but we want them to appear in history still
-- 		while menu.history[#menu.history]~=pages[1] do
-- 			table.remove(menu.history)
-- 		end
-- 		return true
-- 	end
-- 	pages = {
-- 		rm.Page{
-- 			title = title..(#choices>9 and " (1)" or ""),
-- 			description = description,
-- 			choices = {},
-- 			moves = 0 -- number of times the Next/Previous page buttons have been pressed
-- 		}
-- 	}
-- 	for num, choice in ipairs(choices) do
-- 		if #(pages[#pages].choices)==8 and #choices>9 then
-- 			table.insert(pages, rm.Page{
-- 				title = title.." ("..#pages+1 ..")",
-- 				description = description,
-- 				type = "Page",
-- 				choices = {
-- 					rm.Choice{
-- 						name = "Previous page",
-- 						onChoose = function(self, menu, data)
-- 							pages[1].moves = pages[1].moves+1
-- 							return pages[#pages-1]
-- 						end
-- 					}
-- 				}
-- 			})
-- 			table.insert(pages[#pages-1].choices, rm.Choice{
-- 				name = "Next page",
-- 				destination = pages[#pages]
-- 			})
-- 		end
-- 		table.insert(pages[#pages].choices, choice)
-- 	end
-- 	return pages[1]
-- end

-- displays a slice of choices that is generated on-the-fly
-- allows editing after pagination
rm.sliceChoices = function(choices, title, description)
	local page
	page = rm.Page{
		getTitle = function(self, menu, data)
			return title..(#choices>9 and " ("..page.slice..")" or "")
		end,
		description = description,
		getChoices = function(self, menu, data)
			local currentChoices
			if #choices<=9 then
				currentChoices = choices
			else
				local maxSlice = math.ceil(#choices/7)
				if page.slice>maxSlice then
					page.slice = maxSlice
				end
				currentChoices = {}
				local i = 1
				if page.slice>1 then
					table.insert(currentChoices, rm.Choice{
						name = "Previous page",
						onChoose = function(self, menu, data)
							page.slice = page.slice-1>=1 and page.slice-1 or maxSlice
							return page
						end
					})
					-- we can fit 8 choices on the first slice (no back button), and 7 on subsequent slices
					-- also don't count choices for the current slice
					i = 8 + 7*(page.slice-2) + 1
				end
				while #currentChoices<8 and choices[i] do
					table.insert(currentChoices, choices[i])
					i = i+1
				end
				if #currentChoices==8 and choices[i] then
					table.insert(currentChoices, rm.Choice{
						name = "Next page",
						onChoose = function(self, menu, data)
							page.slice = page.slice+1<=maxSlice and page.slice+1 or 1
							return page
						end
					})
				end
			end
			return currentChoices
		end,
		onBack = function(self, menu, data)
			-- so if we later return to this page, we go to the first slice, not wherever we left off
			self.slice = 1
			return true
		end,
		slice = 1
	}
	return page
end

-- big bad send function
rm.send = function(channel, author, menu, data)
	assert(menu.type=="Menu")
	menu.author = author
	menu._isClosed = false

	local message = channel:send{
		embed = {
			description = "Setting up...",
			color = discordia.Color.fromHex("00ff00").value
		}
	}
	menu.message = message

	coroutine.wrap(function() -- wrap it in a coroutine so that the reactions can be added while the message is already set up, to save time
		message:addReaction(rm.reactions.back)
		message:addReaction(rm.reactions.exit)
		for i=1, (menu.maxChoices or 9) do
			if menu._isClosed then return end
			message:addReaction(rm.reactions.choices[i])
		end
		timer.sleep(400) -- without this, the timing of the final reaction feels too quick
	end)()

	menu.history = {}
	local currentPage = menu.startPage
	local nextPage = showPage(message, author, menu, data, currentPage, true)
	while nextPage do
		if nextPage==true then
			nextPage = table.remove(menu.history) or menu.startPage
		elseif currentPage.inHistory and currentPage~=nextPage then
			table.insert(menu.history, currentPage)
		end
		currentPage = nextPage
		nextPage = showPage(message, author, menu, data, nextPage, #menu.history==0)
	end
end

return rm
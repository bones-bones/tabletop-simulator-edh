
----#include Decker
do
    Decker = {}

    -- provide unique ID starting from 20 for present decks
    local nextID
    do
        local _nextID = 20
        nextID = function()
            _nextID = _nextID + 1
            return tostring(_nextID)
        end
    end

    -- Asset signature (equality comparison)
    local function assetSignature(assetData)
        return table.concat({
            assetData.FaceURL,
            assetData.BackURL,
            assetData.NumWidth,
            assetData.NumHeight,
            assetData.BackIsHidden and 'hb' or '',
            assetData.UniqueBack and 'ub' or ''
        })
    end
    -- Asset ID storage to avoid new ones for identical assets
    local idLookup = {}
    local function assetID(assetData)
        local sig = assetSignature(assetData)
        local key = idLookup[sig]
        if not key then
            key = nextID()
            idLookup[sig] = key
        end
        return key
    end

    local assetMeta = {
        deck = function(self, cardNum, options)
            return Decker.AssetDeck(self, cardNum, options)
        end
    }
    assetMeta = {__index = assetMeta}

    -- Create a new CustomDeck asset
    function Decker.Asset(face, back, options)
        local asset = {}
        options = options or {}
        asset.data = {
            FaceURL = face or error('Decker.Asset: faceImg link required'),
            BackURL = back or error('Decker.Asset: backImg link required'),
            NumWidth = options.width or 1,
            NumHeight = options.height or 1,
            BackIsHidden = options.hiddenBack or false,
            UniqueBack = options.uniqueBack or false
        }
        -- Reuse ID if asset existing
        asset.id = assetID(asset.data)
        return setmetatable(asset, assetMeta)
    end
    -- Pull a Decker.Asset from card JSONs CustomDeck entry
    local function assetFromData(assetData)
        return setmetatable({data = assetData, id = assetID(assetData)}, assetMeta)
    end

    -- Create a base for JSON objects
    function Decker.BaseObject()
        return {
            Name = 'Base',
            Transform = {
                posX = 0, posY = 5, posZ = 0,
                rotX = 0, rotY = 0, rotZ = 0,
                scaleX = 1, scaleY = 1, scaleZ = 1
            },
            Nickname = '',
            Description = '',
            ColorDiffuse = { r = 1, g = 1, b = 1 },
            Locked = false,
            Grid = true,
            Snap = true,
            Autoraise = true,
            Sticky = true,
            Tooltip = true,
            GridProjection = false,
            Hands = false,
            XmlUI = '',
            LuaScript = '',
            LuaScriptState = '',
            GUID = 'deadbf'
        }
    end
    -- Typical paramters map with defaults
    local commonMap = {
        name   = {field = 'Nickname',    default = ''},
        desc   = {field = 'Description', default = ''},
        script = {field = 'LuaScript',   default = ''},
        xmlui  = {field = 'XmlUI',       default = ''},
        scriptState = {field = 'LuaScriptState', default = ''},
        locked  = {field = 'Locked',  default = false},
        tooltip = {field = 'Tooltip', default = true},
        guid    = {field = 'GUID',    default = 'deadbf'},
    }
    -- Apply some basic parameters on base JSON object
    function Decker.SetCommonOptions(obj, options)
        options = options or {}
        for k,v in pairs(commonMap) do
            -- can't use and/or logic cause of boolean fields
            if options[k] ~= nil then
                obj[v.field] = options[k]
            else
                obj[v.field] = v.default
            end
        end
        -- passthrough unrecognized keys
        for k,v in pairs(options) do
            if not commonMap[k] then
                obj[k] = v
            end
        end
    end
    -- default spawnObjectJSON params since it doesn't like blank fields
    local function defaultParams(params, json)
        params = params or {}
        params.json = json
        params.position = params.position or {0, 5, 0}
        params.rotation = params.rotation or {0, 0, 0}
        params.scale = params.scale or {1, 1, 1}
        if params.sound == nil then
            params.sound = true
        end
        return params
    end

    -- For copy method
    local deepcopy
    deepcopy = function(t)
        local copy = {}
        for k,v in pairs(t) do
           if type(v) == 'table' then
               copy[k] = deepcopy(v)
           else
               copy[k] = v
           end
        end
        return copy
    end
    -- meta for all Decker derived objects
    local commonMeta = {
        -- return object JSON string, used cached if present
        _cache = function(self)
            if not self.json then
                self.json = JSON.encode(self.data)
            end
            return self.json
        end,
        -- invalidate JSON string cache
        _recache = function(self)
            self.json = nil
            return self
        end,
        spawn = function(self, params)
            params = defaultParams(params, self:_cache())
            return spawnObjectJSON(params)
        end,
        copy = function(self)
            return setmetatable(deepcopy(self), getmetatable(self))
        end,
        setCommon = function(self, options)
            Decker.SetCommonOptions(self.data, options)
            return self
        end,
    }
    -- apply common part on a specific metatable
    local function customMeta(mt)
        for k,v in pairs(commonMeta) do
            mt[k] = v
        end
        mt.__index = mt
        return mt
    end

    -- DeckerCard metatable
    local cardMeta = {
        setAsset = function(self, asset)
            local cardIndex = self.data.CardID:sub(-2, -1)
            self.data.CardID = asset.id .. cardIndex
            self.data.CustomDeck = {[asset.id] = asset.data}
            return self:_recache()
        end,
        getAsset = function(self)
            local deckID = next(self.data.CustomDeck)
            return assetFromData(self.data.CustomDeck[deckID])
        end,
        -- reset deck ID to a consistent value script-wise
        _recheckDeckID = function(self)
            local oldID = next(self.data.CustomDeck)
            local correctID = assetID(self.data.CustomDeck[oldID])
            if oldID ~= correctID then
                local cardIndex = self.data.CardID:sub(-2, -1)
                self.data.CardID = correctID .. cardIndex
                self.data.CustomDeck[correctID] = self.data.CustomDeck[oldID]
                self.data.CustomDeck[oldID] = nil
            end
            return self
        end
    }
    cardMeta = customMeta(cardMeta)
    -- Create a DeckerCard from an asset
    function Decker.Card(asset, row, col, options)
        row, col = row or 1, col or 1
        options = options or {}
        local card = Decker.BaseObject()
        card.Name = 'Card'
        -- optional custom fields
        Decker.SetCommonOptions(card, options)
        if options.sideways ~= nil then
            card.SidewaysCard = options.sideways
            -- FIXME passthrough set that field, find some more elegant solution
            card.sideways = nil
        end
        -- CardID string is parent deck ID concat with its 0-based index (always two digits)
        local num = (row-1)*asset.data.NumWidth + col - 1
        num = string.format('%02d', num)
        card.CardID = asset.id .. num
        -- just the parent asset reference needed
        card.CustomDeck = {[asset.id] = asset.data}

        local obj = setmetatable({data = card}, cardMeta)
        obj:_cache()
        return obj
    end


    -- DeckerDeck meta
    local deckMeta = {
        count = function(self)
            return #self.data.DeckIDs
        end,
        -- Transform index into positive
        index = function(self, ind)
            if ind < 0 then
                return self:count() + ind + 1
            else
                return ind
            end
        end,
        swap = function(self, i1, i2)
            local ri1, ri2 = self:index(i1), self:index(i2)
            assert(ri1 > 0 and ri1 <= self:count(), 'DeckObj.rearrange: index ' .. i1 .. ' out of bounds')
            assert(ri2 > 0 and ri2 <= self:count(), 'DeckObj.rearrange: index ' .. i2 .. ' out of bounds')
            self.data.DeckIDs[ri1], self.data.DeckIDs[ri2] = self.data.DeckIDs[ri2], self.data.DeckIDs[ri1]
            local co = self.data.ContainedObjects
            co[ri1], co[ri2] = co[ri2], co[ri1]
            return self:_recache()
        end,
        -- rebuild self.data.CustomDeck based on contained cards
        _rescanDeckIDs = function(self, id)
            local cardIDs = {}
            for k,card in ipairs(self.data.ContainedObjects) do
                local cardID = next(card.CustomDeck)
                if not cardIDs[cardID] then
                    cardIDs[cardID] = card.CustomDeck[cardID]
                end
            end
            -- eeh, GC gotta earn its keep as well
            -- FIXME if someone does shitton of removals, may cause performance issues?
            self.data.CustomDeck = cardIDs
        end,
        remove = function(self, ind, skipRescan)
            local rind = self:index(ind)
            assert(rind > 0 and rind <= self:count(), 'DeckObj.remove: index ' .. ind .. ' out of bounds')
            local card = self.data.ContainedObjects[rind]
            table.remove(self.data.DeckIDs, rind)
            table.remove(self.data.ContainedObjects, rind)
            if not skipRescan then
                self:_rescanDeckIDs(next(card.CustomDeck))
            end
            return self:_recache()
        end,
        removeMany = function(self, ...)
            local indices = {...}
            table.sort(indices, function(e1,e2) return self:index(e1) > self:index(e2) end)
            for _,ind in ipairs(indices) do
                self:remove(ind, true)
            end
            self:_rescanDeckIDs()
            return self:_recache()
        end,
        insert = function(self, card, ind)
            ind = ind or (self:count() + 1)
            local rind = self:index(ind)
            assert(rind > 0 and rind <= (self:count()+1), 'DeckObj.insert: index ' .. ind .. ' out of bounds')
            table.insert(self.data.DeckIDs, rind, card.data.CardID)
            table.insert(self.data.ContainedObjects, rind, card.data)
            local id = next(card.data.CustomDeck)
            if not self.data.CustomDeck[id] then
                self.data.CustomDeck[id] = card.data.CustomDeck[id]
            end
            return self:_recache()
        end,
        reverse = function(self)
            local s,e = 1, self:count()
            while s < e do
                self:swap(s, e)
                s = s+1
                e = e-1
            end
            return self:_recache()
        end,
        cardAt = function(self, ind)
            local rind = self:index(ind)
            assert(rind > 0 and rind <= (self:count()+1), 'DeckObj.insert: index ' .. ind .. ' out of bounds')
            local card = setmetatable({data = deepcopy(self.data.ContainedObjects[rind])}, cardMeta)
            card:_cache()
            return card
        end,
        switchAssets = function(self, replaceTable)
            -- destructure replace table into
            -- [ID_to_replace] -> [ID_to_replace_with]
            -- [new_asset_ID] -> [new_asset_data]
            local idReplace = {}
            local assets = {}
            for oldAsset, newAsset in pairs(replaceTable) do
                assets[newAsset.id] = newAsset.data
                idReplace[oldAsset.id] = newAsset.id
            end
            -- update deckIDs
            for k,cardID in ipairs(self.data.DeckIDs) do
                local deckID, cardInd = cardID:sub(1, -3), cardID:sub(-2, -1)
                if idReplace[deckID] then
                    self.data.DeckIDs[k] = idReplace[deckID] .. cardInd
                end
            end
            -- update CustomDeck data - nil replaced
            for replacedID in pairs(idReplace) do
                if self.data.CustomDeck[replacedID] then
                    self.data.CustomDeck[replacedID] = nil
                end
            end
            -- update CustomDeck data - add replacing
            for _,replacingID in pairs(idReplace) do
                self.data.CustomDeck[replacingID] = assets[replacingID]
            end
            -- update card data
            for k,cardData in ipairs(self.data.ContainedObjects) do
                local deckID = next(cardData.CustomDeck)
                if idReplace[deckID] then
                    cardData.CustomDeck[deckID] = nil
                    cardData.CustomDeck[idReplace[deckID]] = assets[idReplace[deckID]]
                end
            end
            return self:_recache()
        end,
        getAssets = function(self)
            local assets = {}
            for id,assetData in pairs(self.data.CustomDeck) do
                assets[#assets+1] = assetFromData(assetData)
            end
            return assets
        end
    }
    deckMeta = customMeta(deckMeta)
    -- Create DeckerDeck object from DeckerCards
    function Decker.Deck(cards, options)
        assert(#cards > 1, 'Trying to create a Decker.deck with less than 2 cards')
        local deck = Decker.BaseObject()
        deck.Name = 'Deck'
        Decker.SetCommonOptions(deck, options)
        deck.DeckIDs = {}
        deck.CustomDeck = {}
        deck.ContainedObjects = {}
        for _,card in ipairs(cards) do
            deck.DeckIDs[#deck.DeckIDs+1] = card.data.CardID
            local id = next(card.data.CustomDeck)
            if not deck.CustomDeck[id] then
                deck.CustomDeck[id] = card.data.CustomDeck[id]
            end
            deck.ContainedObjects[#deck.ContainedObjects+1] = card.data
        end

        local obj = setmetatable({data = deck}, deckMeta)
        obj:_cache()
        return obj
    end
    -- Create DeckerDeck from an asset using X cards on its sheet
    function Decker.AssetDeck(asset, cardNum, options)
        cardNum = cardNum or asset.data.NumWidth * asset.data.NumHeight
        local row, col, width = 1, 1, asset.data.NumWidth
        local cards = {}
        for k=1,cardNum do
            cards[#cards+1] = Decker.Card(asset, row, col)
            col = col+1
            if col > width then
                row, col = row+1, 1
            end
        end
        return Decker.Deck(cards, options)
    end
end

----#include Decker

webURL = ""
multiverseBaseURL = "https://api.scryfall.com/cards/"
defaultCardBack = "https://gamepedia.cursecdn.com/mtgsalvation_gamepedia/f/f8/Magic_card_back.jpg?version=0ddc8d41c3b69c2c3c4bb5d72669ffd7"
tappedoutBaseURL = "https://tappedout.net/mtg-decks/"
deckName = "My Deck"
cardLoadCount = 0
deckLoadDone = false
deckLoadTime = os.time()
cardList = {}
sideboardCardList = {}
twoSidedCardList = {}
sideboardTwoSidedCardList = {}
outputObj = nil
showingUI = false



function onLoad()
--[[
    self.createButton({
        click_function = "btnToggleUI",
        function_owner = self,
        label          = "Open Interface",
        scale          = {x=3,y=3,z=3},
        position       = {0, 3, -4},
        rotation       = {0, 0, 0},
        width          = 800,
        height         = 10,
        font_size      = 50,
        color          = {0.9, 0.9, 0.9, 1},
        font_color     = {0, 0, 0},
        tooltip        = "Click to open loader interface",
    })
    ]]--
    showUI(self)

end

function hideUI(obj)
    local inputs = obj.getInputs()
    for i,v in pairs(inputs) do
        if v.input_function == "txtHelp" then
            self.removeInput(v.index)
        elseif v.input_function == "txtDeckChanged" then
            self.removeInput(v.index)
        end
    end

    local inputs = obj.getButtons()
    for i,v in pairs(inputs) do
        print (v.click_function)
        if v.click_function == "btnLoadDeck" then
            self.removeButton(v.index)
        elseif v.click_function == "btnToggleUI" then
            self.editButton({index = v.index, label="Open Interface", tooltip="Click to open loader interface"})
        end
    end
end

function showUI(obj)

--[[
    self.createInput({
        input_function = "txtHelp",
        function_owner = self,
        label          = "",
        alignment      = 2,
                scale          = {x=0.5,y=0.5,z=0.5},
        position       = {x=0, y=1, z=4},
        rotation       = {0, 180, 0},
        width          = 3000,
        height         = 1200,
        font_size      = 200,
        validation     = 1,
        value = "Paste the slug from a tappedout.net deck below.\n\nFor example: 15-03-19-kaalia-edh-deck\n\nThis doesn't support sideboards yet.",
        font_color     = { r=0,b=0,g=0 },
    })
]]--
    self.createInput({
        input_function = "txtDeckChanged",
        function_owner = self,
        label          = "Enter deck slug.",
        alignment      = 2,
        scale          = {x=2,y=2,z=3},
        position       = {x=0, y=0.6, z=4.8},
        rotation       = {0, 0, 0},
        width          = 3800,
        height         = 300,
        font_size      = 200,
        validation     = 1,
        value = "",
        font_color     = { r=0,b=0,g=0 },
    })


    self.createButton({
        click_function = "btnLoadDeck",
        function_owner = self,
        label          = "Load Deck",
        scale          = {x=2,y=2,z=3.5},
        position       = {0, 1, 7},
        rotation       = {0, 0, 0},
        width          = 850,
        height         = 275,
        font_size      = 175,
        color          = {0.5, 0.5, 0.5},
        font_color     = {1, 1, 1},
        tooltip        = "Click to load deck.",
    })

    local inputs = obj.getButtons()
    for i,v in pairs(inputs) do
        if v.click_function == "btnToggleUI" then
            self.editButton({index = v.index, label = "Close Interface", tooltip = "Click to close loader interface"})
        end
    end
end

function btnToggleUI(obj, color, alt_click)
    if showingUI then
        hideUI(obj)
        showingUI = false
    else
        showUI(obj)
        showingUI = true
    end

end

function txtHelp()
end

--   FUNCTION - Callback when text is changed in deck text input
function txtDeckChanged(obj, color, input, stillEditing)
    if not stillEditing then
    end
end

function sendOutput(str)
    printToAll(str)
end


--   FUNCTION - Callback
function btnLoadDeck(obj, color, alt_click)


    -- Let's get the index of the output text input
    local inputs = obj.getInputs()
    for i,v in pairs(inputs) do
        url = v.value
        if v.input_function == "txtOutput" then
            --outputBoxIndex = v.index
        elseif v.input_function == "txtDeckChanged" then
            deckName = trim(v.value)
            webURL = tappedoutBaseURL .. cleanSlug(v.value) .. "/"
        end
    end

    if string.len(deckName) == 0 then
        sendOutput("Enter a deck slug from tappedout.net")
        return
    end

--print (webURL)
    --webURL = webURL

-- https://tappedout.net/mtg-decks/15-03-19-kaalia-edh-deck/?fmt=multiverse
    cardList = {}
    sideboardCardList = {}
    sideboardTwoSidedCardList = {}
    twoSidedCardList = {}
    cardLoadCount = 0
    deckLoadDone = false

    sendOutput("Fetching Deck: " .. webURL .. "?fmt=multiverse")
    sendOutput("Please wait...")
    --[[
    -- Create a timer that displays a message every 2 seconds to show that it is still loading
    Wait.condition(
        function() printToAll("Done loading") end,
        function()
            if (deckLoadTime + 2 < os.time()) then
--                printToAll("loading...")
                deckLoadTime = os.time()
            end
            return deckLoadDone
        end,
        20
    )
    ]]--

    WebRequest.get(webURL .. "?fmt=multiverse",
    function(webReturn)
        if webReturn.is_error then print("ERROR") end
        if string.len(webReturn.text) == 0 then print("Empty response") end
        fetchDeckText(obj, webReturn.text)

    end)
end

function fetchDeckText(obj, multiverseDeck)
    WebRequest.get(webURL .. "?fmt=txt",
    function(webReturn2)
        if webReturn2.is_error then print("ERROR") end
        if string.len(webReturn2.text) == 0 then print("Empty response") end

        processDeckString(multiverseDeck, webReturn2.text,
        function()
            if cardLoadCount == 0 then
                deckLoadDone = true
                assembleDeck(obj)
            end
        end)
    end)
end

function cleanSlug(s)
    if s then
        return (s:gsub("^[%s%W]*(.-)[%s%W\n]*$", "%1"))
    else
        return ""
    end
end


function trim(s)
    if s then
        --s = s:gsub("\n", "")
        return (s:gsub("^[%s]*(.-)[%s\n]*$", "%1"))
    else
        return ""
    end
end

function processDeckString(cardList, cardList2, callback)
    local sideboardCard = false
    local cardListArr = {}
    local cardList2Arr = {}
    local i=1;
    local multiverseURL

    for line in getLines(cardList) do
        if string.len(trim(line)) > 0 then
            cardListArr[i] = line
            i=i+1
        end
    end

    i=1
    for line in getLines(cardList2) do
        if string.len(trim(line)) > 0 then
            cardList2Arr[i] = line
            i=i+1
        end
    end

    i=1
    while cardListArr[i] do
        line = cardListArr[i]

        local data, qty, multiverseNumber

        if string.len(trim(line)) > 0 then

            if string.find(line,"SB:") then
                sideboardCard = true
            else
                for k, v in line:gmatch("(%d+)%s+(.+)") do
                    qty = k
                    multiverseNumber = v
                end

                if (string.len(trim(multiverseNumber)) > 0 and trim(multiverseNumber) != "0") then
                    multiverseURL = multiverseBaseURL .. "multiverse/" .. multiverseNumber
                else
                    sendOutput("Missing multiverse id. Using fallback from text export for card: " .. cardList2Arr[i])
                    for k, v in cardList2Arr[i]:gmatch("(%d+)%s+(.+)") do
                        qty = k
                        multiverseNumber = v
                    end
                    multiverseURL = multiverseBaseURL .. "named?exact=" .. multiverseNumber
                end

                    cardLoadCount = cardLoadCount + tonumber(qty)

                    if sideboardCard then
                        WebRequest.get(multiverseURL,
                            function(webReturn)
                                if webReturn.is_error then print("ERROR: Cannot get card data.") end
                                if string.len(webReturn.text) == 0 then print("Empty response while getting card data.") end

                                local success, data = pcall(function() return JSON.decode(webReturn.text) end)

                                if data == nil then print("Card data empty.") end
                                if not success then print("Error fetching card: " .. WebReturn.url) end
                                if data.object == "error" then
                                    sendOutput("Error - Can't find card: " .. multiverseNumber .. " - " .. data.code .. " (Deck will be incomplete)")
                                    cardLoadCount = cardLoadCount - tonumber(qty)
                                else
                                    for i = 1,qty,1 do
                                        addCardToDeck(data, multiverseNumber, true)
                                        callback()
                                    end
                                end
                            end)
                    else
                        WebRequest.get(multiverseURL,
                            function(webReturn)
                                if webReturn.is_error then print("ERROR: Cannot get card data.") end
                                if string.len(webReturn.text) == 0 then print("Empty response while getting card data.") end

                                local success, data = pcall(function() return JSON.decode(webReturn.text) end)

                                if data == nil then print("Card data empty.") end
                                if not success then print("Error fetching card: " .. WebReturn.url) end

                                if data.object == "error" then
                                    sendOutput("Error - Can't find card: " .. multiverseNumber .. " - " .. data.code .. " (Deck will be incomplete)" .. cardList2Arr[i])
                                    cardLoadCount = cardLoadCount - tonumber(qty)
                                else
                                    for i = 1,qty,1 do
                                        addCardToDeck(data, multiverseNumber, false)
                                        callback()
                                    end
                                end
                            end)
                    end

            end
        end
        i=i+1
    end
end

function addCardToDeck(json, multiverseNumber, sideboardCard)
    --print("Card Name: " .. json.name)
    local imageFaceURL
    local imageBackURL
    local twoSided = false

    if not json then
        sendOutput("No json data for card")
        return
    end

    -- Need to handle cards with two sides
    if json.image_uris then
        imageFaceURL = json.image_uris.normal
        oracleText = json.oracle_text
    elseif json.card_faces then
        -- This card has two faces
        imageFaceURL = json.card_faces[1].image_uris.normal
        imageBackURL = json.card_faces[2].image_uris.normal
        oracleText = json.card_faces[1].oracle_text .. "\n" .. json.card_faces[2].oracle_text
        twoSided = true
    else
        sendOutput("Missing images - Deck will be incomplete")
        imageFaceURL = defaultCardBack
        imageBackURL = defaultCardBack
        oracleText = "Missing images for multiverse id: " .. multiverseNumber
    end

    local cardAsset = Decker.Asset(imageFaceURL, defaultCardBack, {width = 1, height = 1, hiddenBack = true })

    -- define cards on the asset, skipping three because we can (would be row 2, column 1)
    local card = Decker.Card(cardAsset, 1, 1) -- (asset, row, column)
    card:setCommon({name = json.name .. "(" .. json.set_name .. ")", desc = oracle_text})
    if sideboardCard then
--        print("Adding card to sideboard")
        sideboardCardList[#sideboardCardList+1] = card  -- add the card to the cardList array
    else
--        print("Adding card to deck")
        cardList[#cardList+1] = card  -- add the card to the cardList array
    end

    if twoSided then
        local twoSidedCardAsset = Decker.Asset(imageFaceURL, imageBackURL, {width = 1, height = 1, hiddenBack = true})

        if sideboardCard then
            local twoSidedCard = Decker.Card(twoSidedCardAsset, 1, 1) -- (asset, row, column)
            twoSidedCard:setCommon({name = json.name, desc = oracle_text})
            sideboardTwoSidedCardList[#sideboardTwoSidedCardList+1] = twoSidedCard  -- add the card to the cardList array
        else
            local twoSidedCard = Decker.Card(twoSidedCardAsset, 1, 1) -- (asset, row, column)
            twoSidedCard:setCommon({name = json.name, desc = oracle_text})
            twoSidedCardList[#twoSidedCardList+1] = twoSidedCard  -- add the card to the cardList array
        end
    end

    cardLoadCount = cardLoadCount - 1;  -- decrement the cardLoadCount counter
end

function assembleDeck(obj)
    local rotation = obj.getRotation()

    -- Spawn in the main deck
    local myDeck = Decker.Deck(cardList)
    local spawnDeck = myDeck:spawn({position = self.positionToWorld({x=4.5,y=7,z=-2}),  rotation = {0, rotation.y, 180}})
    sendOutput("Spawning deck")
    spawnDeck.setName(deckName)

    -- Handle when we have to spawn in a deck or card that with two faces
    if #twoSidedCardList > 0 then
        if #twoSidedCardList > 1 then
            local twoSidedDeck = Decker.Deck(twoSidedCardList)
            local spawnTwoSidedDeck = twoSidedDeck:spawn({position = self.positionToWorld({x=1.5,y=7,z=-2}),  rotation = {0, rotation.y, 180}})
            sendOutput("Spawning two sided cards deck")
            spawnTwoSidedDeck.setName(deckName .. " - Two sided cards")
        else
            local twoSidedCard = twoSidedCardList[1]
            local spawnTwoSidedCard = twoSidedCard:spawn({position = self.positionToWorld({x=1.5,y=7,z=-2}),  rotation = {0, rotation.y, 180}})
            sendOutput("Spawning two sided card")
            --spawnDeck.setName(deckName .. " - Two sided cards")
        end
    end

    if #sideboardCardList > 0 then
        local myDeck = Decker.Deck(sideboardCardList)
        local spawnDeck = myDeck:spawn({position = self.positionToWorld({x=-1.5,y=7,z=-2}),  rotation = {0, rotation.y, 180}})
        sendOutput("Spawning sideboard deck")
        spawnDeck.setName(deckName .. " - Sideboard")
    end

    if #sideboardTwoSidedCardList > 0 then
        if #sideboardTwoSidedCardList > 1 then
            local twoSidedDeck = Decker.Deck(sideboardTwoSidedCardList)
            local spawnTwoSidedDeck = twoSidedDeck:spawn({position = self.positionToWorld({x=-4.5,y=7,z=-2}),  rotation = {0, rotation.y, 180}})
            sendOutput("Spawning two-sided sideboard cards deck")
            spawnTwoSidedDeck.setName(deckName .. " - Sideboard two sided cards")
        else
            local twoSidedCard = sideboardTwoSidedCardList[1]
            local spawnTwoSidedCard = twoSidedCard:spawn({position = self.positionToWorld({x=-4.5,y=7,z=-2}),  rotation = {0, rotation.y, 180}})
            sendOutput("Spawning two-sided sideboard card")
            --spawnDeck.setName(deckName .. " - Two sided cards")
        end
    end
end

-- break up a string with multiple lines into an iterator
function getLines(s)
    if s:sub(-1)~="\n" then s=s.."\n" end
    return s:gmatch("(.-)\n")
end

-- FUNCTION - Helper to print contents of a table
function tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      tprint(v, indent+1)
    elseif type(v) == 'boolean' then
      print(formatting .. tostring(v))
    else
      print(formatting .. v)
    end
  end
end

-- FUNCTION - Helper to print contents of a table
local function print_r ( t )
    local print_r_cache={}
        local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            print(indent.."*"..tostring(t))
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                local tLen = #t
                for i = 1, tLen do
                    local val = t[i]
                    if (type(val)=="table") then
                        print(indent.."#["..i.."] => "..tostring(t).." {")
                        sub_print_r(val,indent..string.rep(" ",string.len(i)+8))
                        print(indent..string.rep(" ",string.len(i)+6).."}")
                    elseif (type(val)=="string") then
                        print(indent.."#["..i..'] => "'..val..'"')
                    else
                        print(indent.."#["..i.."] => "..tostring(val))
                    end
                end
                for pos,val in pairs(t) do
                    if type(pos) ~= "number" or math.floor(pos) ~= pos or (pos < 1 or pos > tLen) then
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

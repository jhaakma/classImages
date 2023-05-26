local config = require("classImages.config")
local logger = require("logging.logger").new{ name = "classImages" }

for _, e in ipairs(config.imagePieces) do
    local ImagePiece = require("classImages.components.ImagePiece")
    logger:info("registering %s", e.texture)
    ImagePiece.register(e)
end

---@param e uiActivatedEventData
local function updateClassImage(e)
    ---@class ClassImages.ImageConfig[]
    local imageConfigs = {
        MenuLevelUp = {
            imageBlockName = "MenuLevelUp_Picture",
            width = 390,
            height = 198,
            parentWidth = 390,
            parentHeight = 198,
        },
        MenuChooseClass = {
            imageBlockName = "MenuChooseClass_description",
            width = 256,
            height = 128,
            parentWidth = 264,
            parentHeight = 136,
        }
    }
    local imageConfig = imageConfigs[e.element.name]

    local MAX_PIECES = 20

    local inspect = require("inspect").inspect
    local logger = require("logging.logger").new{
        name = "livecoding",
        logLevel = "DEBUG",
    }
    local ImagePiece = require("classImages.components.ImagePiece")



    ---@param piece ClassImages.ImagePiece
    local function validForClass(piece)
        local class = tes3.player.object.class
        logger:debug("checking %s is valid for class %s", piece.texture, class.name)

        local specialisation = class.specialization
        local attributes = class.attributes
        local majorSkills = table.invert(class.majorSkills)
        local minorSkills = table.invert(class.minorSkills)
        local allSkills = table.copy(majorSkills, table.copy(minorSkills))

        --class id reqs
        logger:trace("0. checking %d class reqs", table.size(piece.classRequirements))
        if table.size(piece.classRequirements) > 0 then
            for _, classRequirement in ipairs(piece.classRequirements) do
                logger:debug("checking %s", classRequirement.type)
                if classRequirement.type:lower() == class.id:lower() then
                    logger:info("PASSED (class id)")
                    return true
                else
                    logger:info("FAILED")
                    return false
                end
            end
        end

        --skill reqs
        logger:trace("1. checking %d skill reqs", table.size(piece.skillRequirements))
        local hasOne = false
        for _, skillRequirement in ipairs(piece.skillRequirements) do
            logger:debug("checking %s", table.find(tes3.skill, skillRequirement.type) or skillRequirement.type)
            local skillsTable
            if skillRequirement.type == "major" then
                logger:debug("- major")
                skillsTable = majorSkills
            elseif skillRequirement.type == "minor" then
                logger:debug("- minor")
                skillsTable = minorSkills
            else
                skillsTable = allSkills
            end

            if not piece.isOr then
                if skillRequirement.negative then
                    logger:debug("- negative")
                    if skillsTable[skillRequirement.type] then
                        logger:info("FAILED")
                        return false
                    end
                else
                    logger:debug("- positive")
                    if not skillsTable[skillRequirement.type] then
                        logger:info("FAILED")
                        --logger:info(inspect(skillsTable))
                        return false
                    end
                end
            else
                if skillRequirement.negative then
                    logger:debug("- negative")
                    if skillsTable[skillRequirement.type] then
                        hasOne = true
                    end
                else
                    logger:debug("- positive")
                    if skillsTable[skillRequirement.type] then
                        hasOne = true
                    end
                end
            end
        end

        if piece.isOr and not hasOne then
            logger:info("isOr FAILED")
            return false
        end
        logger:info("skills PASSED")
        --atrribute reqs
        logger:trace("2. checking %d attribute reqs", table.size(piece.attributeRequirements))
        for _, attributeRequirement in ipairs(piece.attributeRequirements) do
            logger:debug("checking %s", table.find(tes3.attribute, attributeRequirement.type))
            if attributeRequirement.negative then
                logger:debug("- negative")
                if attributes[1] == attributeRequirement.type
                    or attributes[2] == attributeRequirement.type
                then
                    logger:info("FAILED")
                    return false
                end
            else
                logger:debug("- positive")
                if attributes[1] ~= attributeRequirement.type
                    and attributes[2] ~= attributeRequirement.type
                then
                    logger:info("FAILED")
                    return false
                end
            end
        end
        logger:info("attributes PASSED")
        --specialisation req
        logger:debug("3. checking %d specialisation reqs", table.size(piece.specialisationRequirements))
        for _, specialisationRequirement in ipairs(piece.specialisationRequirements) do
            logger:debug("checking %s", table.find(tes3.specialization, specialisationRequirement.type))
            if specialisationRequirement.negative then
                logger:debug("- negative")
                if specialisation == specialisationRequirement.type then
                    logger:info("FAILED")
                    return false
                end
            else
                if specialisation ~= specialisationRequirement.type then
                    logger:info("FAILED")
                    return false
                end
            end
        end

        logger:info("specialisation PASSED")
        return true
    end

    local function hasFreeSlot(slots, piece)
        logger:debug("checking slots")
        for _, slot in ipairs(piece.slots) do
            if slots[slot] then
                logger:debug("slot %s is filled", slot)
                return false
            end
        end
        logger:debug("slots are free")
        return true
    end

    ---@param piecesAdded table<string, number>
    ---@param piece ClassImages.ImagePiece
    local function checkExclusions(piecesAdded, piece)
        logger:debug("checking exclusions")
        for _, exclusion in ipairs(piece.excludedPieces) do
            logger:warn("checking %s against %s", exclusion, inspect(table.keys(piecesAdded)))
            if piecesAdded[exclusion] then
                logger:debug("exclusion %s is filled", exclusion)
                return false
            end
        end
        logger:debug("exclusions are free")
        return true
    end

    ---@param hasShield boolean
    ---@param piece ClassImages.ImagePiece
    local function checkShieldState(hasShield, piece)
        if piece.shieldState == "requiresShield" then
            if not hasShield then
                return false
            end
        elseif piece.shieldState == "requiresNoShield" then
            if hasShield then
                return false
            end
        end
        return true
    end


    local function checkIsFiller(piece)
        logger:debug("checking isFiller")
        if piece.isFiller then
            logger:debug("is filler")
            return true
        end
        logger:debug("is not filler")
        return false
    end

    ---Onyl one gold piece allowed
    ---@param hasGold boolean
    ---@param piece ClassImages.ImagePiece
    local function checkGold(hasGold, piece)
        if hasGold == true and piece.isGold == true then
            return false
        end
        return true
    end

    local function addImage(parent, imagePath)
        local image = parent:createImage{
            path = "textures\\classImages\\" .. imagePath .. ".tga"
        }
        image.width = imageConfig.width
        image.height = imageConfig.height
        image.scaleMode = true
        image.absolutePosAlignX = 0.5
        image.absolutePosAlignY = 0.5
    end

    ---@param e uiActivatedEventData
    local function doUpdate(e)
        tes3.messageBox("Player class: %s", tes3.player.object.class.name)
        local classImageBlock = e.element:findChild(imageConfig.imageBlockName)
        if not classImageBlock then
            logger:error("%s not found", imageConfig.imageBlockName)
            return
        end
        logger:info(classImageBlock.name)
        classImageBlock:destroyChildren()
        classImageBlock.minWidth = imageConfig.parentWidth
        classImageBlock.minHeight = imageConfig.parentHeight
        -- classImageBlock.width = imageConfig.parentWidth
        -- classImageBlock.height = imageConfig.parentHeight
--            classImageBlock.paddingAllSides = 0

        addImage(classImageBlock, "0.background")

        ---@type table<ClassImages.ImagePiece.slot, boolean>
        local slots = {
            Below_Left_1 = false,
            Below_Left_2 = false,
            Below_Left_3 = false,
            Below_Left_4 = false,
            Below_Left_5 = false,
            Below_Middle = false,
            Below_Right_1 = false,
            Below_Right_2 = false,
            Below_Right_3 = false,
            Background_Left = false,
            Background_Middle = false,
            Background_Right = false,
            Midground_Left = false,
            Midground_Middle = false,
            Midground_Right = false,
            Foreground_Left = false,
            Foreground_Middle = false,
            Foreground_Right = false,
            Above_Left_1 = false,
            Above_Left_2 = false,
            Above_Left_3 = false,
            Above_Left_4 = false,
            Above_Left_5 = false,
            Above_Middle = false,
            Above_Right_1 = false,
            Above_Right_2 = false,
            Above_Right_3 = false,
            Above_Right_4 = false,
            Above_Right_5 = false,
        }
        local count = 0
        local piecesAdded = {}
        local hasShield = false
        local hasGold = false
        logger:info("CHECKING CLASS %s", tes3.player.object.class.name)

        local function processPiece(piece, doFiller)
            if count >= MAX_PIECES then
                logger:error("Max items reached")
                return false
            end
            logger:debug("checking piece %s", piece.texture)
            local valid = validForClass(piece)
                and hasFreeSlot(slots, piece)
                and checkIsFiller(piece) == doFiller
                and checkShieldState(hasShield, piece)
                and checkExclusions(piecesAdded, piece)
                and checkGold(hasGold, piece)
            if valid then
                logger:warn("---- Piece %s is valid, adding image", piece.texture)
                count = count + 1
                piecesAdded[piece.priority] = piece
                if piece.isGold then
                    hasGold = true
                end
                if piece.shieldState == "isShield" then
                    hasShield = true
                end
                for _, slot in ipairs(piece.slots) do
                    logger:debug("Slot %s is filled", slot)
                    slots[slot] = true
                end

            else
                logger:error("---- Piece %s is not valid", piece.texture)
            end
            return true
        end

        local pieces = ImagePiece.registeredPieces

        for _, piece in pairs(pieces ) do
            if not processPiece(piece, false) then break end
        end
        for _, piece in pairs(pieces ) do
            if not processPiece(piece, true) then break end
        end

        local slotOrder = {
            "Background_Left",
            "Background_Middle",
            "Background_Right",
            "Midground_Left",
            "Midground_Middle",
            "Midground_Right",
            "Foreground_Left",
            "Foreground_Middle",
            "Foreground_Right",
            "Below_Left_1",
            "Below_Left_2",
            "Below_Left_3",
            "Below_Left_4",
            "Below_Left_5",
            "Below_Middle",
            "Below_Right_1",
            "Below_Right_2",
            "Below_Right_3",
            "Above_Left_1",
            "Above_Left_2",
            "Above_Left_3",
            "Above_Left_4",
            "Above_Left_5",
            "Above_Middle",
            "Above_Right_1",
            "Above_Right_2",
            "Above_Right_3",
            "Above_Right_4",
            "Above_Right_5",
            }
        for _, slot in ipairs(slotOrder) do
            for _, piece in pairs(piecesAdded) do
                if table.find(piece.slots, slot) then
                    logger:debug("adding %s : %s", piece.priority, piece.texture)
                    addImage(classImageBlock, piece.texture)
                    --remove from pieces
                    piecesAdded[piece.priority] = nil
                end
            end
        end
        addImage(classImageBlock, "0.vignette")
        e.element:updateLayout()
    end

    if imageConfig then
        local classList = e.element:findChild("MenuChooseClass_ClassScroll")
        if classList then
            classList = classList:getContentElement()
            for _, button in ipairs(classList.children) do
                button:registerAfter("mouseClick", function()
                    doUpdate(e)
                end)
            end
        end
        doUpdate(e)
    end
end
event.register("uiActivated", updateClassImage)
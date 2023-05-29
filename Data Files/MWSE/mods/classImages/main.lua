require("classImages.mcm")
local config = require("classImages.config")
local common = require("classImages.common")
local ImagePiece = require("classImages.components.ImagePiece")
local inspect = require("inspect").inspect
local MAX_PIECES = 15
local logger = common.createLogger("main")
for _, e in ipairs(config.imagePieces) do
    logger:debug("registering %s", e.texture)
    ImagePiece.register(e)
end

---@param piece ClassImages.ImagePiece
---@param class tes3class
local function checkClassRequirements(piece, class)
    logger:debug("    checking %d class reqs", table.size(piece.classRequirements))
    if table.size(piece.classRequirements) > 0 then
        for _, classRequirement in ipairs(piece.classRequirements) do
            logger:debug("    checking %s", classRequirement.type)
            if classRequirement.type:lower() == class.id:lower() then
                logger:debug("    PASSED (class id)")
                return true
            else
                logger:debug("    %s FAILED - missing class requirement %s", piece.texture, classRequirement.type)
                return false
            end
        end
    end
end

---@param piece ClassImages.ImagePiece
---@param class tes3class
local function checkSkillRequirements(piece, class)
    logger:debug("    1. checking %d skill reqs", table.size(piece.skillRequirements))
    local majorSkills = table.invert(class.majorSkills)
    local minorSkills = table.invert(class.minorSkills)
    local allSkills = table.copy(majorSkills, table.copy(minorSkills))
    local hasOne = false
    for _, skillRequirement in ipairs(piece.skillRequirements) do
        local skillname = table.find(tes3.skill, skillRequirement.type)
        logger:debug("    checking %s", skillname)
        local skillsTable
        if skillRequirement.major == true then
            logger:debug("    - major")
            skillsTable = majorSkills
        elseif skillRequirement.minor == true then
            logger:debug("    - minor")
            skillsTable = minorSkills
        else
            skillsTable = allSkills
        end

        if piece.isOr then
            logger:debug("    is OR")
            if skillRequirement.negative then
                logger:debug("    - negative")
                if skillsTable[skillRequirement.type] then
                    hasOne = true
                end
            else
                logger:debug("    - positive")
                if skillsTable[skillRequirement.type] then
                    hasOne = true
                end
            end
        else
            logger:debug("    is AND")
            if skillRequirement.negative then
                logger:debug("    - negative")
                if skillsTable[skillRequirement.type] then
                    logger:debug("    %s FAILED - has negative skill requirement %s", piece.texture, skillname)
                    return false
                end
            else
                logger:debug("    - positive")
                if not skillsTable[skillRequirement.type] then
                    logger:debug("    %s FAILED - missing positive skill requirement %s", piece.texture, skillname)
                    return false
                end
            end
        end
    end

    if piece.isOr == true and not hasOne then
        logger:debug("    %s FAILED - No skill requirements met (isOr=true)", piece.texture)
        return false
    end

    return true
end

---@param piece ClassImages.ImagePiece
---@param class tes3class
local function checkAttributeRequirements(piece, class)
    local attributes = class.attributes
    logger:debug("    2. checking %d attribute reqs", table.size(piece.attributeRequirements))
    for _, attributeRequirement in ipairs(piece.attributeRequirements) do
        local attrName = table.find(tes3.attribute, attributeRequirement.type)
        logger:debug("    checking %s", attrName)
        if attributeRequirement.negative then
            logger:debug("    - negative")
            if attributes[1] == attributeRequirement.type
                or attributes[2] == attributeRequirement.type
            then
                logger:debug("    %s FAILED - has negative attr requirement %s", piece.texture, attrName)
                return false
            end
        else
            logger:debug("    - positive")
            if attributes[1] ~= attributeRequirement.type
                and attributes[2] ~= attributeRequirement.type
            then
                logger:debug("    %s FAILED - missing positive attr requirement %s", piece.texture, attrName)
                return false
            end
        end
    end

    return true
end

local function checkSpecialization(piece, class)
    local specialisation = class.specialization
    logger:debug("    3. checking %d specialisation reqs", table.size(piece.specialisationRequirements))
    for _, specialisationRequirement in ipairs(piece.specialisationRequirements) do
        local specName = table.find(tes3.specialization, specialisationRequirement.type)
        logger:debug("    checking %s", specName)
        if specialisationRequirement.negative then
            logger:debug("    - negative")
            if specialisation == specialisationRequirement.type then
                logger:debug("    %s FAILED - has negative spec requirement %s", piece.texture, specName)
                return false
            end
        else
            if specialisation ~= specialisationRequirement.type then
                logger:debug("    %s FAILED - missing positive spec requirement %s", piece.texture, specName)
                return false
            end
        end
    end

    return true
end

local function hasFreeSlot(slots, piece)
    logger:debug("    checking slots")
    for _, slot in ipairs(piece.slots) do
        if slots[slot] then
            logger:debug("    %s FAILED - slot %s is filled", piece.texture, slot)
            return false
        end
    end
    logger:debug("    slots PASSED")
    return true
end

---@param piecesAdded table<string, number>
---@param piece ClassImages.ImagePiece
local function checkExclusions(piecesAdded, piece)
    logger:debug("    checking exclusions")
    for _, exclusion in ipairs(piece.excludedPieces) do
        logger:debug("     - checking %s against  exclusions - %s", exclusion, inspect(table.keys(piecesAdded)))
        if piecesAdded[exclusion] then
            logger:debug(    "%s FAILED - exclusion %s is filled", piece.texture, exclusion)
            return false
        end
    end
    logger:debug("    exclusions PASSED")
    return true
end

---@param piece ClassImages.ImagePiece
local function validForClass(piece)
    local class = tes3.player.object.class
    logger:debug("    checking %s is valid for class %s", piece.texture, class.name)

    ----------------------------------
    -- Class
    -- Unlike the other checks, this one returns if true (matches expected class)
    -- or false (does not match expected class). If nil, there is no class
    -- requirement so continue checking.
    ----------------------------------
    local classRequirement = checkClassRequirements(piece, class)
    if classRequirement ~= nil then
        return classRequirement
    end
    logger:debug("    class PASSED")

    ----------------------------------
    -- Skills
    ----------------------------------
    if not checkSkillRequirements(piece, class) then
        return false
    end
    logger:debug("    skills PASSED")

    ----------------------------------
    -- Attributes
    ----------------------------------
    if not checkAttributeRequirements(piece, class) then
        return false
    end
    logger:debug("    attributes PASSED")

    ----------------------------------
    -- Specialisation
    ----------------------------------
    if not checkSpecialization(piece, class) then
        return false
    end

    logger:debug("    specialisation PASSED")
    return true
end

---@param hasShield boolean
---@param piece ClassImages.ImagePiece
local function checkShieldState(hasShield, piece)
    logger:debug("    checking shield state. hasShield=%s, state=%s", hasShield, piece.shieldState)
    if piece.shieldState == "requiresShield" then
        if not hasShield then
            logger:debug("    %s FAILED - requires shield", piece.texture)
            return false
        end
    elseif piece.shieldState == "noShield" then
        if hasShield then
            logger:debug("    %s FAILED - requires no shield", piece.texture)
            return false
        end
    end
    logger:debug("    shield state PASSED")
    return true
end

---@param piece ClassImages.ImagePiece
local function checkIsFiller(piece)
    if piece.isFiller then
        return true
    end
    return false
end

---Onyl one gold piece allowed
---@param hasGold boolean
---@param piece ClassImages.ImagePiece
local function checkGold(hasGold, piece)
    if hasGold == true and piece.isGold == true then
        logger:debug("%s FAILED - gold already present", piece.texture)
        return false
    end
    return true
end

--- Adds the piece to the class image
---@param imageConfig ClassImages.ImageConfig
---@param parent tes3uiElement
---@param imagePath string
local function addImage(imageConfig, parent, imagePath)
    local image = parent:createImage{
        path = "textures\\classImages\\" .. imagePath .. ".tga"
    }
    image.width = imageConfig.width
    image.height = imageConfig.height
    image.scaleMode = true
    image.absolutePosAlignX = 0.5
    image.absolutePosAlignY = 0.5
end

---@class ClassImage.processPiece.processData
---@field slots table<ClassImages.ImagePiece.slot, boolean>
---@field piecesAdded table<string, number>
---@field count number
---@field hasShield boolean
---@field hasGold boolean
---@field doFiller boolean

---@param processData ClassImage.processPiece.processData
---@param piece ClassImages.ImagePiece
local function processPiece(processData, piece)
    logger:debug("Filler: %s. Priority: %s", processData.doFiller, piece.priority)

    if not checkIsFiller(piece) == processData.doFiller then
        return true
    end
    if processData.count >= MAX_PIECES then
        logger:debug("Max items reached")
        return false
    end
    logger:debug("----------------------------")
    logger:debug("CHECKING PIECE %s", piece.texture)
    logger:debug("----------------------------")

    local valid = validForClass(piece)
        and hasFreeSlot(processData.slots, piece)
        and checkShieldState(processData.hasShield, piece)
        and checkExclusions(processData.piecesAdded, piece)
        and checkGold(processData.hasGold, piece)
    if valid then
        processData.piecesAdded[piece.priority] = piece
        if piece.isGold then
            processData.hasGold = true
        end
        if piece.shieldState == "isShield" then
            logger:debug("    - piece is a shield, set hasShield to true")
            processData.hasShield = true
        end
        for _, slot in ipairs(piece.slots) do
            logger:debug("    Filled slot %s", slot)
            logger:assert(processData.slots[slot] ~= true, "Slot already filled")
            processData.slots[slot] = true
            processData.count = processData.count + 1
        end
        logger:debug("------------------------------------------------")
        logger:debug("---- Piece %s is valid, image added", piece.texture)
        logger:debug("------------------------------------------------")
    else
        logger:debug("------------------------------------------------")
        logger:debug("---- Piece %s is not valid", piece.texture)
        logger:debug("------------------------------------------------")
    end
    logger:debug("\n")
    return true
end

local function initProcessData()
    return {
        slots = {
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
            Above_Middle = false,
            Above_Right_1 = false,
            Above_Right_2 = false,
            Above_Right_3 = false,
            Above_Right_4 = false,
            Above_Right_5 = false,
            Above_Left_5 = false,
        },
        piecesAdded = {},
        count = 0,
        hasShield = false,
        hasGold = false,
        doFiller = false
    }
end

local function getSlotOrder()
    return {
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
        "Above_Middle",
        "Above_Right_1",
        "Above_Right_2",
        "Above_Right_3",
        "Above_Right_4",
        "Above_Right_5",
        "Above_Left_5",
    }
end

--- Update the class image
---@param imageConfig ClassImages.ImageConfig
---@param e uiActivatedEventData
local function doUpdate(imageConfig, e)
    if not config.mcm.enabled then
        logger:trace("Disabled")
        return
    end
    local classImageBlock = e.element:findChild(imageConfig.imageBlockName)
    if not classImageBlock then
        logger:error("%s not found", imageConfig.imageBlockName)
        return
    end
    logger:debug(classImageBlock.name)
    --set up image block
    classImageBlock:destroyChildren()
    classImageBlock.minWidth = imageConfig.parentWidth
    classImageBlock.minHeight = imageConfig.parentHeight
    --add background
    addImage(imageConfig, classImageBlock, "0.background")
    logger:debug("CHECKING CLASS %s", tes3.player.object.class.name)
    --Process pieces
    local pieces = ImagePiece:getRegisteredPieces()
    local processData = initProcessData()
    for i, piece in pairs(pieces) do
        logger:debug("non filler %d", i)
        if not processPiece(processData, piece) then break end
    end
    for i, piece in pairs(pieces) do
        logger:debug("filler %d", i)
        processData.doFiller = true
        if not processPiece(processData, piece) then break end
    end
    --add images in order of slot
    for _, slot in ipairs(getSlotOrder()) do
        for _, piece in pairs(processData.piecesAdded) do
            if table.find(piece.slots, slot) then
                logger:debug("adding %s : %s", piece.priority, piece.texture)
                addImage(imageConfig, classImageBlock, piece.texture)
                --remove from pieces
                processData.piecesAdded[piece.priority] = nil
            end
        end
    end
    --add vignette
    addImage(imageConfig, classImageBlock, "0.vignette")
    e.element:updateLayout()
end

---@param e uiActivatedEventData
local function updateClassImage(e)
    local imageConfig = config.menuData[e.element.name]
    if imageConfig then
        local classList = e.element:findChild("MenuChooseClass_ClassScroll")
        if classList then
            classList = classList:getContentElement()
            for _, button in ipairs(classList.children) do
                button:registerAfter("mouseClick", function()
                    doUpdate(imageConfig, e)
                end)
            end
        end
        doUpdate(imageConfig, e)
    end
end
event.register("uiActivated", updateClassImage)
-- Human Hunters (race 1, class 3)
--
-- Stock 3.3.5a has no Human Hunter. The server allows a race/class combination
-- as soon as `playercreateinfo` has a row for it; the client only shows the
-- class button once CharBaseInfo.dbc lists it (shipped separately in patch-4.mpq).
--
-- Re-applicable: every block is DELETE then INSERT on fixed keys.
-- Everything here is read at startup, so it takes effect after a worldserver restart.

-- Start in Northshire Abbey, same spot as every other Human class.
DELETE FROM `playercreateinfo` WHERE `race` = 1 AND `class` = 3;
INSERT INTO `playercreateinfo` (`race`, `class`, `map`, `zone`, `position_x`, `position_y`, `position_z`, `orientation`) VALUES
(1, 3, 0, 12, -8949.95, -132.493, 83.5312, 0);

-- Action bar: the Dwarf Hunter layout (Attack, Raptor Strike, Auto Shot), with the
-- Human racial Every Man for Himself on button 9 like the other Human classes.
DELETE FROM `playercreateinfo_action` WHERE `race` = 1 AND `class` = 3;
INSERT INTO `playercreateinfo_action` (`race`, `class`, `button`, `action`, `type`) VALUES
(1, 3, 0, 6603, 0),
(1, 3, 1, 2973, 0),
(1, 3, 2, 75, 0),
(1, 3, 9, 59752, 0);

-- Starting Guns skill (stock row is raceMask 36 = Dwarf + Tauren only).
DELETE FROM `playercreateinfo_skills` WHERE `raceMask` = 1 AND `classMask` = 4 AND `skill` = 46;
INSERT INTO `playercreateinfo_skills` (`raceMask`, `classMask`, `skill`, `rank`, `comment`) VALUES
(1, 4, 46, 0, 'Guns (Human Hunter)');

-- SkillRaceClassInfo overrides: the stock hunter rows for these weapon skills leave
-- out the Human bit, so a Human Hunter could never hold the skill (and
-- playercreateinfo_skills silently drops it). Same rows as the DBC, raceMask | 1.
DELETE FROM `skillraceclassinfo_dbc` WHERE `ID` IN (117, 133, 632);
INSERT INTO `skillraceclassinfo_dbc` (`ID`, `SkillID`, `RaceMask`, `ClassMask`, `Flags`, `MinLevel`, `SkillTierID`, `SkillCostIndex`) VALUES
(117, 44, 167, 4, 128, 0, 0, 0),   -- Axes    (was 166)
(133, 46, 37, 4, 128, 0, 0, 0),    -- Guns    (was 36)
(632, 173, 1191, 4, 128, 0, 0, 0); -- Daggers (was 1190)

-- Starting gear: copy of the Dwarf Hunter outfit (DBC rows 21/49) as new IDs 368/369.
-- Rugged Trapper's shirt/pants/boots, Worn Battleaxe, Small Ammo Pouch,
-- Old Blunderbuss, Light Shot, Hearthstone.
DELETE FROM `charstartoutfit_dbc` WHERE `ID` IN (368, 369);
INSERT INTO `charstartoutfit_dbc` VALUES
(368, 1, 3, 0, 0,
 148, 147, 129, 0, 12282, -1, 2102, 2508, 2516, -1, 6948, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
 9976, 9975, 9977, -1, 22291, -1, 1816, 6606, 5998, -1, 6418, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
 4, 7, 8, -1, 17, -1, 18, 26, 24, -1, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1),
(369, 1, 3, 1, 0,
 148, 147, 129, 0, 12282, -1, 2102, 2508, 2516, -1, 6948, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
 9976, 9975, 9977, -1, 22291, -1, 1816, 6606, 5998, -1, 6418, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
 4, 7, 8, -1, 17, -1, 18, 26, 24, -1, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);

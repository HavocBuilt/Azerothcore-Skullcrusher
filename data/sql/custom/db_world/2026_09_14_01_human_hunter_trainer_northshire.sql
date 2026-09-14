-- Human Hunters: Northshire hunter trainer (900017)
--
-- Northshire Abbey has no hunter trainer. This is the Human counterpart of
-- Thorgas Grimson (895), Coldridge Valley's starter hunter trainer: same stats
-- and same level 2-6 spell list (trainer 8). Later ranks come from the Goldshire
-- trainer and the three hunter trainers in Stormwind's Dwarven District.
--
-- Differences from Thorgas: human model and gun (Westfall Brigade Hunter, 27462),
-- Stormwind faction, and the Draenei hunter trainers' gossip menu 7262 instead of
-- 4675, whose text is written in Dwarf dialect. Menu 7262 has the same three
-- options and the same hunter-only conditions.
--
-- Re-applicable: DELETE then INSERT on fixed keys. Loaded at startup.

DELETE FROM `creature_template` WHERE `entry` = 900017;
INSERT INTO `creature_template` (`entry`, `difficulty_entry_1`, `difficulty_entry_2`, `difficulty_entry_3`, `KillCredit1`, `KillCredit2`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `speed_swim`, `speed_flight`, `detection_range`, `rank`, `dmgschool`, `DamageModifier`, `BaseAttackTime`, `RangeAttackTime`, `BaseVariance`, `RangeVariance`, `unit_class`, `unit_flags`, `unit_flags2`, `dynamicflags`, `family`, `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `PetSpellDataId`, `VehicleId`, `mingold`, `maxgold`, `AIName`, `MovementType`, `HoverHeight`, `HealthModifier`, `ManaModifier`, `ArmorModifier`, `ExperienceModifier`, `RacialLeader`, `movementId`, `RegenHealth`, `CreatureImmunitiesId`, `flags_extra`, `ScriptName`, `VerifiedBuild`) VALUES
(900017, 0, 0, 0, 0, 0, 'Garret Hollis', 'Hunter Trainer', NULL, 7262, 5, 5, 0, 12, 49, 1, 1.14286, 1, 1, 18, 0, 0, 1, 1500, 2000, 1, 1, 1, 0, 2048, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 2, '', 12340);

DELETE FROM `creature_template_model` WHERE `CreatureID` = 900017;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(900017, 0, 24650, 1, 1, NULL);

-- bytes2 = 2: ranged weapon shown, as on Thorgas.
DELETE FROM `creature_template_addon` WHERE `entry` = 900017;
INSERT INTO `creature_template_addon` (`entry`, `path_id`, `mount`, `bytes1`, `bytes2`, `emote`, `visibilityDistanceType`, `auras`) VALUES
(900017, 0, 0, 0, 2, 0, 0, NULL);

DELETE FROM `creature_equip_template` WHERE `CreatureID` = 900017;
INSERT INTO `creature_equip_template` (`CreatureID`, `ID`, `ItemID1`, `ItemID2`, `ItemID3`, `VerifiedBuild`) VALUES
(900017, 1, 0, 0, 4383, NULL);

-- Trainer 8 (level required): Track Beasts 2, Serpent Sting 4, Aspect of the Monkey 4,
-- Hunter's Mark 6, Arcane Shot 6.
DELETE FROM `creature_default_trainer` WHERE `CreatureId` = 900017;
INSERT INTO `creature_default_trainer` (`CreatureId`, `TrainerId`) VALUES
(900017, 8);

-- Spawn: Northshire Abbey front yard, facing the Human start point by the steps.
DELETE FROM `creature` WHERE `guid` = 5300900 OR `id` = 900017;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `VerifiedBuild`, `CreateObject`, `Comment`) VALUES
(5300900, 900017, 0, 0, 0, 1, 1, 1, -8932.9, -136.33, 83.15, 2.92, 180, 0, 0, 102, 0, 0, 0, 0, 0, '', NULL, 0, 'Human Hunters: Northshire hunter trainer');

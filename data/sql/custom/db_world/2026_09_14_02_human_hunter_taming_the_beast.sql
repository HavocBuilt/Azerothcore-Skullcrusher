-- Human Hunters: Goldshire hunter trainer (900018) and the Elwynn "Taming the Beast" chain
--
-- Every stock Taming the Beast chain is locked to one race. This is the Human one,
-- run entirely from Goldshire:
--
--   900100 The Hunter's Path    Stormwind hunter trainers -> Ada Brightwood (breadcrumb)
--   900101 Taming the Beast     tame a Stonetusk Boar     (Ada -> Ada)
--   900102 Taming the Beast     tame a Gray Forest Wolf   (Ada -> Ada)
--   900103 Taming the Beast     tame a Young Forest Bear  (Ada -> Ada), rewards Tame Beast
--   900104 Training the Beast   Ada -> Erma, Goldshire's stable master, rewards Beast Training
--
-- How the taming works. The chain reuses the three Dwarf taming rods, because new
-- spells would have to be added to both the server and client Spell.dbc, which are
-- not in sync on this realm:
--
--   rod 15911 -> spell 19674 -> on success core casts 19677 (charm + completes quest 6064)
--   rod 15913 -> spell 19687 -> on success core casts 19676 (charm + completes quest 6084)
--   rod 15908 -> spell 19548 -> on success core casts 19597 (charm + completes quest 6085)
--
--   1. `conditions` (source 17) limit each rod spell to one creature entry. An extra
--      ElseGroup adds the Elwynn beast as a second valid target.
--   2. The success spell's quest-complete effect names the Dwarf quest, so it does
--      nothing for a Human. Instead, the beast's SmartAI catches that success spell
--      (SPELLHIT) and credits the Human quest to the caster (CALL_AREAEXPLOREDOREVENTHAPPENS).
--      The charm is already on the beast when SpellHit is delivered, so the event needs
--      SMART_EVENT_FLAG_WHILE_CHARMED (0x200) or SmartAI skips it. Hunter taming leaves
--      the creature's AI enabled (only warlock demon charms switch AI off), so SpellHit
--      does reach SmartAI.
--
-- The rods' tooltips still name the Dwarf beasts ("Begins taming a Large Crag Boar");
-- that text lives in the client Spell.dbc.
--
-- Re-applicable: DELETE then INSERT on fixed keys; UPDATEs set fixed values. Loaded at startup.

-- ---------------------------------------------------------------------------
-- Ada Brightwood <Hunter Trainer>, Goldshire. Full hunter trainer list (trainer 7,
-- same as the Stormwind trainers), human female hunter model, bow.
-- ---------------------------------------------------------------------------
DELETE FROM `creature_template` WHERE `entry` = 900018;
INSERT INTO `creature_template` (`entry`, `difficulty_entry_1`, `difficulty_entry_2`, `difficulty_entry_3`, `KillCredit1`, `KillCredit2`, `name`, `subname`, `IconName`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`, `faction`, `npcflag`, `speed_walk`, `speed_run`, `speed_swim`, `speed_flight`, `detection_range`, `rank`, `dmgschool`, `DamageModifier`, `BaseAttackTime`, `RangeAttackTime`, `BaseVariance`, `RangeVariance`, `unit_class`, `unit_flags`, `unit_flags2`, `dynamicflags`, `family`, `type`, `type_flags`, `lootid`, `pickpocketloot`, `skinloot`, `PetSpellDataId`, `VehicleId`, `mingold`, `maxgold`, `AIName`, `MovementType`, `HoverHeight`, `HealthModifier`, `ManaModifier`, `ArmorModifier`, `ExperienceModifier`, `RacialLeader`, `movementId`, `RegenHealth`, `CreatureImmunitiesId`, `flags_extra`, `ScriptName`, `VerifiedBuild`) VALUES
(900018, 0, 0, 0, 0, 0, 'Ada Brightwood', 'Hunter Trainer', NULL, 7262, 10, 10, 0, 12, 51, 1, 1.14286, 1, 1, 18, 0, 0, 1, 1500, 2000, 1, 1, 1, 0, 2048, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, '', 0, 1, 1, 1, 1, 1, 0, 0, 1, 0, 2, '', 12340);

DELETE FROM `creature_template_model` WHERE `CreatureID` = 900018;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(900018, 0, 30190, 1, 1, NULL);

DELETE FROM `creature_template_addon` WHERE `entry` = 900018;
INSERT INTO `creature_template_addon` (`entry`, `path_id`, `mount`, `bytes1`, `bytes2`, `emote`, `visibilityDistanceType`, `auras`) VALUES
(900018, 0, 0, 0, 2, 0, 0, NULL);

-- Hornwood Recurve Bow in the ranged slot.
DELETE FROM `creature_equip_template` WHERE `CreatureID` = 900018;
INSERT INTO `creature_equip_template` (`CreatureID`, `ID`, `ItemID1`, `ItemID2`, `ItemID3`, `VerifiedBuild`) VALUES
(900018, 1, 0, 0, 2506, NULL);

DELETE FROM `creature_default_trainer` WHERE `CreatureId` = 900018;
INSERT INTO `creature_default_trainer` (`CreatureId`, `TrainerId`) VALUES
(900018, 7);

-- Spawn: Goldshire, beside Erma the stable master outside the Lion's Pride Inn.
DELETE FROM `creature` WHERE `guid` = 5300901 OR `id` = 900018;
INSERT INTO `creature` (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`, `position_x`, `position_y`, `position_z`, `orientation`, `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`, `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `VerifiedBuild`, `CreateObject`, `Comment`) VALUES
(5300901, 900018, 0, 0, 0, 1, 1, 1, -9461.5, 44.5, 56.85, 1.47, 180, 0, 0, 0, 0, 0, 0, 0, 0, '', NULL, 0, 'Human Hunters: Goldshire hunter trainer');

-- Erma <Stable Master> ends Training the Beast, so she needs the quest giver flag
-- (stock npcflag 4194305 = gossip + stable master).
UPDATE `creature_template` SET `npcflag` = 4194307 WHERE `entry` = 6749;

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------
DELETE FROM `quest_template` WHERE `ID` BETWEEN 900100 AND 900104;
INSERT INTO `quest_template` (`ID`, `QuestType`, `QuestLevel`, `MinLevel`, `QuestSortID`, `RewardNextQuest`, `RewardXPDifficulty`, `RewardDisplaySpell`, `RewardSpell`, `StartItem`, `Flags`, `AllowableRaces`, `LogTitle`, `LogDescription`, `QuestDescription`, `AreaDescription`, `QuestCompletionLog`, `RequiredItemId1`, `RequiredItemCount1`, `VerifiedBuild`) VALUES
(900100, 2, -1, 10, -261, 900101, 1, 0, 0, 0, 8, 1,
 'The Hunter\'s Path',
 'Speak with Ada Brightwood in Goldshire.',
 'You have come a long way, $N, and you handle yourself well. It is time you had a companion at your side.$B$BTravel to Goldshire and find Ada Brightwood outside the Lion\'s Pride Inn. She will teach you how to tame a beast of your own.',
 '', '', 0, 0, 12340),
(900101, 2, -1, 10, -261, 900102, 5, 0, 0, 15911, 2, 1,
 'Taming the Beast',
 'Use the Taming Rod to tame a Stonetusk Boar. Practice your skills, then return the Taming Rod to Ada Brightwood in Goldshire.',
 'So you want a pet of your own? Good. No two hunters are alike, and neither are their companions, so the best way to learn is to try a few and see which suits you.$B$BWe will start with something stubborn. Stonetusk boars root through the farmlands south of Goldshire. They are thick-skinned and hard to put down, which makes them fine protectors.$B$BTake this taming rod, find a stonetusk boar and use the rod on it. Hold its attention until it is yours, then come back to me.',
 'Tame a Stonetusk Boar', 'Return to Ada Brightwood in Goldshire.', 15911, 1, 12340),
(900102, 2, -1, 10, -261, 900103, 5, 0, 0, 15913, 2, 1,
 'Taming the Beast',
 'Use the Taming Rod to tame a Gray Forest Wolf. Practice your skills, then return the Taming Rod to Ada Brightwood in Goldshire.',
 'The boar is strong, but not every hunter wants to stand behind a wall of bristles. A wolf is quicker, and it hunts the way you do: patient, then all at once.$B$BGray forest wolves roam the woods east of Goldshire. Take this taming rod and see how a wolf feels at your side.',
 'Tame a Gray Forest Wolf', 'Return to Ada Brightwood in Goldshire.', 15913, 1, 12340),
(900103, 2, -1, 10, -261, 900104, 5, 23356, 1579, 15908, 2, 1,
 'Taming the Beast',
 'Use the Taming Rod to tame a Young Forest Bear. Practice your skills, then return the Taming Rod to Ada Brightwood in Goldshire.',
 'One more. A bear is slow to anger and slower to fall, and there is no better companion to take a beating in your place.$B$BYoung forest bears live in the woods southeast of Goldshire. Tame one with this rod.$B$BWhen you return, I will teach you to tame any beast you choose, and to call and dismiss it as you please. Your companion will face what you face, and grow stronger alongside you.',
 'Tame a Young Forest Bear', 'Return to Ada Brightwood in Goldshire.', 15908, 1, 12340),
(900104, 2, -1, 10, -261, 0, 3, 23357, 5300, 0, 8, 1,
 'Training the Beast',
 'Speak with Erma, the stable master in Goldshire.',
 'You can tame a beast now, $N, but a pet needs more than a leash. It needs feeding, and care when it falls.$B$BErma keeps the stables right here outside the inn, and she knows animals better than anyone in Elwynn. Speak with her and she will show you how to look after your companion.',
 '', '', 0, 0, 12340);

DELETE FROM `quest_template_addon` WHERE `ID` BETWEEN 900100 AND 900104;
INSERT INTO `quest_template_addon` (`ID`, `MaxLevel`, `AllowableClasses`, `SourceSpellID`, `PrevQuestID`, `NextQuestID`, `ExclusiveGroup`, `BreadcrumbForQuestId`, `RewardMailTemplateID`, `RewardMailDelay`, `RequiredSkillID`, `RequiredSkillPoints`, `RequiredMinRepFaction`, `RequiredMaxRepFaction`, `RequiredMinRepValue`, `RequiredMaxRepValue`, `ProvidedItemCount`, `SpecialFlags`) VALUES
(900100, 0, 4, 0, 0,      0, 0, 900101, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
(900101, 0, 4, 0, 0,      0, 0, 0,      0, 0, 0, 0, 0, 0, 0, 0, 1, 2),
(900102, 0, 4, 0, 900101, 0, 0, 0,      0, 0, 0, 0, 0, 0, 0, 0, 1, 2),
(900103, 0, 4, 0, 900102, 0, 0, 0,      0, 0, 0, 0, 0, 0, 0, 0, 1, 2),
(900104, 0, 4, 0, 900103, 0, 0, 0,      0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

DELETE FROM `quest_details` WHERE `ID` BETWEEN 900100 AND 900104;
INSERT INTO `quest_details` (`ID`, `Emote1`, `Emote2`, `Emote3`, `Emote4`, `EmoteDelay1`, `EmoteDelay2`, `EmoteDelay3`, `EmoteDelay4`, `VerifiedBuild`) VALUES
(900100, 1, 0, 0, 0, 0, 0, 0, 0, 0),
(900101, 1, 0, 0, 0, 0, 0, 0, 0, 0),
(900102, 1, 0, 0, 0, 0, 0, 0, 0, 0),
(900103, 1, 0, 0, 0, 0, 0, 0, 0, 0),
(900104, 1, 0, 0, 0, 0, 0, 0, 0, 0);

DELETE FROM `quest_request_items` WHERE `ID` BETWEEN 900100 AND 900104;
INSERT INTO `quest_request_items` (`ID`, `EmoteOnComplete`, `EmoteOnIncomplete`, `CompletionText`, `VerifiedBuild`) VALUES
(900101, 1, 1, 'Any luck with the boar, $N? Take your time. You will get to try a few before you have to choose.', 12340),
(900102, 1, 1, 'How did the wolf take to you?', 12340),
(900103, 1, 6, 'Have you tamed the young forest bear yet?', 12340);

DELETE FROM `quest_offer_reward` WHERE `ID` BETWEEN 900100 AND 900104;
INSERT INTO `quest_offer_reward` (`ID`, `Emote1`, `Emote2`, `Emote3`, `Emote4`, `EmoteDelay1`, `EmoteDelay2`, `EmoteDelay3`, `EmoteDelay4`, `RewardText`, `VerifiedBuild`) VALUES
(900100, 1, 0, 0, 0, 0, 0, 0, 0, 'Another hunter from Stormwind? Good. Elwynn has no shortage of beasts, and I have no shortage of patience. Let us get started.', 12340),
(900101, 1, 0, 0, 0, 0, 0, 0, 0, 'Not bad for a first try. A boar will never win a race, but it will never back down either. Let us see what else suits you.', 12340),
(900102, 1, 0, 0, 0, 0, 0, 0, 0, 'You moved well together. Keep that in mind. When I feel you have learned enough, you will be free to choose any companion you like.', 12340),
(900103, 1, 0, 0, 0, 0, 0, 0, 0, 'Well done, $N. Here is what I promised: the power to tame a beast of your own, and to call and dismiss it as you please.$B$BFind a good, loyal companion, and enjoy the hunt.', 12340),
(900104, 1, 0, 0, 0, 0, 0, 0, 0, 'Ada sent you, did she? Then you have a pet to look after.$B$BLet me show you how to feed it, and how to bring it back when it falls. Look after your companion and it will look after you.', 12340);

DELETE FROM `creature_queststarter` WHERE `quest` BETWEEN 900100 AND 900104;
INSERT INTO `creature_queststarter` (`id`, `quest`) VALUES
(5515, 900100),   -- Einris Brightspear, Stormwind
(5516, 900100),   -- Ulfir Ironbeard, Stormwind
(5517, 900100),   -- Thorfin Stoneshield, Stormwind
(900018, 900101),
(900018, 900102),
(900018, 900103),
(900018, 900104);

DELETE FROM `creature_questender` WHERE `quest` BETWEEN 900100 AND 900104;
INSERT INTO `creature_questender` (`id`, `quest`) VALUES
(900018, 900100),
(900018, 900101),
(900018, 900102),
(900018, 900103),
(6749, 900104);    -- Erma, Goldshire stable master

-- ---------------------------------------------------------------------------
-- Taming rods: allow the Elwynn beasts as targets (ElseGroup 1 = OR with the stock row)
-- ---------------------------------------------------------------------------
DELETE FROM `conditions` WHERE `SourceTypeOrReferenceId` = 17 AND `SourceGroup` = 0 AND `ElseGroup` = 1
  AND `ConditionTypeOrReference` = 31 AND ((`SourceEntry` = 19674 AND `ConditionValue2` = 113) OR (`SourceEntry` = 19687 AND `ConditionValue2` = 1922) OR (`SourceEntry` = 19548 AND `ConditionValue2` = 822));
INSERT INTO `conditions` (`SourceTypeOrReferenceId`, `SourceGroup`, `SourceEntry`, `SourceId`, `ElseGroup`, `ConditionTypeOrReference`, `ConditionTarget`, `ConditionValue1`, `ConditionValue2`, `ConditionValue3`, `NegativeCondition`, `ErrorType`, `ErrorTextId`, `ScriptName`, `Comment`) VALUES
(17, 0, 19674, 0, 1, 31, 1, 3, 113, 0, 0, 0, 0, '', 'Tame Large Crag Boar - also Stonetusk Boar (Human Hunter quest 900101)'),
(17, 0, 19687, 0, 1, 31, 1, 3, 1922, 0, 0, 0, 0, '', 'Tame Snow Leopard - also Gray Forest Wolf (Human Hunter quest 900102)'),
(17, 0, 19548, 0, 1, 31, 1, 3, 822, 0, 0, 0, 0, '', 'Tame Ice Claw Bear - also Young Forest Bear (Human Hunter quest 900103)');

-- ---------------------------------------------------------------------------
-- Quest credit: the beast reacts to the taming success spell (id 10 is clear of the
-- stock rows on these creatures). event_flags 512 = SMART_EVENT_FLAG_WHILE_CHARMED.
-- ---------------------------------------------------------------------------
UPDATE `creature_template` SET `AIName` = 'SmartAI' WHERE `entry` = 822;

DELETE FROM `smart_scripts` WHERE `source_type` = 0 AND `id` = 10 AND `entryorguid` IN (113, 1922, 822);
INSERT INTO `smart_scripts` (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`, `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`, `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`, `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`, `target_x`, `target_y`, `target_z`, `target_o`, `comment`) VALUES
(113,  0, 10, 0, 8, 0, 100, 512, 19677, 0, 0, 0, 0, 0, 15, 900101, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 'Stonetusk Boar - On Spellhit \'Tame Large Crag Boar\' (while charmed) - Quest Credit \'Taming the Beast\' (Human Hunter)'),
(1922, 0, 10, 0, 8, 0, 100, 512, 19676, 0, 0, 0, 0, 0, 15, 900102, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 'Gray Forest Wolf - On Spellhit \'Tame Snow Leopard\' (while charmed) - Quest Credit \'Taming the Beast\' (Human Hunter)'),
(822,  0, 10, 0, 8, 0, 100, 512, 19597, 0, 0, 0, 0, 0, 15, 900103, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 'Young Forest Bear - On Spellhit \'Tame Ice Claw Bear\' (while charmed) - Quest Credit \'Taming the Beast\' (Human Hunter)');

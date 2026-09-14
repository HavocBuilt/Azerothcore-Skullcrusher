-- Surname title "%s Merlyn" (CharTitles 178) for one character, Malcolm
--
-- WoW 3.3.5a names are one word, letters only, max 12 characters, so "Malcolm Merlyn"
-- can't be a character name. A title whose text is "%s Merlyn" shows as
-- "Malcolm Merlyn" above his head, on his target frame and in the character window,
-- while chat, whispers and commands keep using "Malcolm".
--
-- Nothing grants this title automatically: achievements and quests only reference
-- stock titles (up to 177), mod-pvp-titles uses the stock PvP rank titles, and
-- playerbots grants none. It is given by hand with `.titles add 178` on the one
-- character, so no other player can select it. Every client still needs the same row
-- in CharTitles.dbc (shipped in patch-4.mpq) to display the title when they see him.
--
-- ID 178 and bit index (Mask_ID) 143 are the first free ones after stock 3.3.5a
-- (IDs stop at 177, bits at 142; the player field holds 192 bits).
-- The string flag 16712190 is what every stock title row uses.
--
-- Re-applicable: DELETE then INSERT. chartitles_dbc is read at startup.

DELETE FROM `chartitles_dbc` WHERE `ID` = 178;
INSERT INTO `chartitles_dbc` (`ID`, `Condition_ID`,
  `Name_Lang_enUS`, `Name_Lang_enGB`, `Name_Lang_koKR`, `Name_Lang_frFR`, `Name_Lang_deDE`, `Name_Lang_enCN`, `Name_Lang_zhCN`, `Name_Lang_enTW`, `Name_Lang_zhTW`, `Name_Lang_esES`, `Name_Lang_esMX`, `Name_Lang_ruRU`, `Name_Lang_ptPT`, `Name_Lang_ptBR`, `Name_Lang_itIT`, `Name_Lang_Unk`, `Name_Lang_Mask`,
  `Name1_Lang_enUS`, `Name1_Lang_enGB`, `Name1_Lang_koKR`, `Name1_Lang_frFR`, `Name1_Lang_deDE`, `Name1_Lang_enCN`, `Name1_Lang_zhCN`, `Name1_Lang_enTW`, `Name1_Lang_zhTW`, `Name1_Lang_esES`, `Name1_Lang_esMX`, `Name1_Lang_ruRU`, `Name1_Lang_ptPT`, `Name1_Lang_ptBR`, `Name1_Lang_itIT`, `Name1_Lang_Unk`, `Name1_Lang_Mask`,
  `Mask_ID`) VALUES
(178, 0,
 '%s Merlyn', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', 16712190,
 '%s Merlyn', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', 16712190,
 143);

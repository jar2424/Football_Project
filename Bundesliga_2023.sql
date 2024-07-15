-- The aim of these queries is to analyze certain goal-scoring patterns in the 2023 Bundesliga season
-- There are 4 main patterns to be analyzed, which shall be visualized using Tableau afterwards (Link at bottom):
	-- Pattern #1: Create a running_total of all goals scored over the whole season 
	-- Pattern #2: Create a map of the stadiums and highlight according to total goals scored there
	-- Pattern #3: Creata a heat map of goals scored by foreigners by clubs
	-- Pattern #4: Create a bar chart with the most successful substitutes (total scorers)
-- Tableau Link: https://public.tableau.com/app/profile/julius.rucha/viz/BundesligaSeaon20232024GoalScoringPatterns/Bundesliga_2324_Goals?publish=yes
-- Database Link: https://www.kaggle.com/datasets/davidcariboo/player-scores/data?



-- Pattern #1: Create a running_total of all goals scored over the whole season

ALTER TABLE games
ADD COLUMN home_goals_from_aggregate text, 
ADD COLUMN away_goals_from_aggregate text, 
ADD COLUMN total_goals numeric, 
ADD COLUMN matchday_nr text, 
ADD COLUMN rolling_goals numeric; 

	-- there's an aggregate column (e.g., 2:1), which needs to be split	
	-- the matchday column (round) has inconsistent naming, it needs to be cleaned
UPDATE games
SET home_goals_from_aggregate = split_part (aggregate, ':', 1), 
	away_goals_from_aggregate = split_part (aggregate, ':', 2),
	matchday_nr = split_part (round, '.', 1); 

	-- aggregate was text; the new columns need to be numeric
ALTER TABLE games
ALTER COLUMN home_goals_from_aggregate TYPE numeric USING home_goals_from_aggregate::numeric, 
ALTER COLUMN away_goals_from_aggregate TYPE numeric USING away_goals_from_aggregate::numeric;

	-- total_goals needs to resembels the sum of home and away goals
UPDATE games
SET total_goals = home_goals_from_aggregate + away_goals_from_aggregate; 

	-- a CTE is needed because of the inconsistencies in the matchday(round) column, otherwise the final select statement wouldn't work
WITH Rolling_Count AS (
	SELECT matchday_nr::numeric, SUM(total_goals) AS total_goals
	FROM games AS g
	JOIN competitions AS c
	ON g.competition_id = c.competition_id
	WHERE competition_code = 'bundesliga'
	AND season = 2023
	GROUP BY matchday_nr
	ORDER BY matchday_nr asc
) 

	-- select matchday, total_goals and rolling_goals
SELECT *, SUM(total_goals) OVER (ORDER BY matchday_nr::numeric ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rolling_goals
FROM Rolling_Count;



-- Pattern #2: -- Pattern #2: Create a map of the stadiums and highlight according to total goals scored there

SELECT stadium, SUM(total_goals) AS total_goals
FROM games AS g
JOIN competitions AS c
ON g.competition_id = c.competition_id
WHERE competition_code = 'bundesliga'
AND season = 2023
GROUP BY stadium
ORDER BY total_goals desc;



-- Pattern #3: Creata a heat map of goals scored by foreigners by clubs

SELECT cl.name, COUNT(game_event_id) AS goals
FROM clubs AS cl
JOIN players AS p
ON p.current_club_id = cl.club_id
JOIN game_events AS ge
ON p.player_id = ge.player_id
JOIN games AS g
ON ge.game_id = g.game_id
JOIN competitions AS c
ON g.competition_id = c.competition_id
WHERE c.competition_code = 'bundesliga'
	AND g.season = 2023
	AND ge.type = 'Goals'
	AND p.country_of_citizenship != 'Germany'
	AND cl.domestic_competition_id = 'L1'
GROUP BY cl.name
ORDER BY goals desc;



-- Pattern #4: Create a bar chart with the most successful substitutes (total scorers)

	-- Create a CTE containing all Substitutes
WITH substitutes AS (
	SELECT player_in_id, game_id
	FROM game_events
	WHERE type = 'Substitutions'
)

	-- Search for 10 best scorers (goals + assists) after being subbed in 
SELECT p.name, SUM(a.goals) AS goals, SUM(a.assists) AS assists, (SUM(a.goals)+SUM(a.assists)) AS total_scorers
FROM appearances AS a
JOIN players AS p
ON p.player_id = a.player_id
JOIN games AS g
ON a.game_id = g.game_id
JOIN competitions AS c
ON g.competition_id = c.competition_id
JOIN Substitutes AS s
ON a.player_id = s.player_in_id
AND a.game_id = s.game_id
WHERE c.competition_code = 'bundesliga'
AND g.season = 2023
GROUP BY p.name
ORDER BY total_scorers desc
LIMIT 10;
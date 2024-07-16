-- These queries shall give information on outstanding goal scoring performances in Europe's Top 5 Football Leagues since 2012
-- Furthermore they will give more background info on these performances
-- The code is written in a way to make it easily visualizable for Tableau
-- The Tableau Story can be found here: https://public.tableau.com/app/profile/julius.rucha/viz/OutstandinggoalscoringperformancesinEuropesTop5FootballLeaguessince2012/final_goal_scoring_story?publish=yes
-- The database can be found here: https://www.kaggle.com/datasets/davidcariboo/player-scores/data?

-- The following 4 patterns will be analyzed:
	-- Pattern #1: Which players have the highest goal-scoring & win correlation for their club?
	-- Pattern #2: Which players had a sudden steep increase in goals scored compared to their former average?
	-- Pattern #3: Which players scored the fastest consecutive hattricks?
	-- Pattern #4: Which players shot the most total goals in 1 season?
-- Afterwards, the Nr. 1 player in all of the above categories will have the following things analyzed concerning the respective season, in which it happened:
	-- Analysis #1: In which minutes did he score in that season?
	-- Analysis #2: Where does his amount of goals scored rank among his other seasons?
	-- Analysis #3: What are the values for the KPIs 'Minutes per Goal' and 'Goals per Match'?



-- Pattern #1: Which players have the highest goal-scoring & win correlation for their club?

SELECT 
    player_name,
    club_name,
    season,
    total_goals,
    games_won_when_played,
    games_won_when_scored,
    goal_win_correlation_percentage,
    RANK() OVER (ORDER BY goal_win_correlation_percentage DESC) AS rank
FROM (
    SELECT 
        p.name AS player_name,
        cl.name AS club_name, 
        g.season,
        SUM(a.goals) AS total_goals, 
        SUM(CASE WHEN cg.own_goals > cg.opponent_goals THEN 1 ELSE 0 END) AS games_won_when_played,
        SUM(CASE WHEN a.goals > 0 AND cg.own_goals > cg.opponent_goals THEN 1 ELSE 0 END) AS games_won_when_scored,
        ROUND(
            (
                (SUM(CASE WHEN a.goals > 0 AND cg.own_goals > cg.opponent_goals THEN 1 ELSE 0 END))::numeric
                / NULLIF(SUM(CASE WHEN cg.own_goals > cg.opponent_goals THEN 1 ELSE 0 END), 0)::numeric
            ) * 100, 
            2
        ) AS goal_win_correlation_percentage
    FROM games AS g
    JOIN club_games AS cg ON g.game_id = cg.game_id
    JOIN appearances AS a ON g.game_id = a.game_id
    JOIN players AS p ON a.player_id = p.player_id
    JOIN competitions AS c ON g.competition_id = c.competition_id
    JOIN clubs AS cl ON cg.club_id = cl.club_id
    WHERE c.competition_code IN ('bundesliga', 'laliga', 'serie-a', 'ligue-1', 'premier-league')
    GROUP BY p.name, cl.name, g.season
    HAVING SUM(a.goals) > 10 -- Condition 1: Minimum of 10 goals have to be scored (to only target real impactful attackers)
        AND SUM(CASE WHEN cg.own_goals > cg.opponent_goals THEN 1 ELSE 0 END) >= 10 -- Condition 2: Minimum of 10 games won, while he was on the pitch
) AS subquery
ORDER BY rank ASC
LIMIT 100;
-- Sandro Ramirez has scored in all 11 games Malaga CF won in the 2016/2017 season



-- Pattern #2: Which players had a sudden steep increase in goals scored compared to their former average?

WITH player_season_counts AS (
    SELECT
        p.player_id,
        COUNT(DISTINCT g.season) AS num_seasons
    FROM players AS p
    JOIN appearances AS a ON p.player_id = a.player_id
    JOIN games AS g ON a.game_id = g.game_id
    JOIN competitions AS c ON g.competition_id = c.competition_id
    WHERE c.competition_code IN ('bundesliga', 'laliga', 'serie-a', 'ligue-1', 'premier-league')
    GROUP BY p.player_id
    HAVING COUNT(DISTINCT g.season) >= 5
), 
goals_by_season AS (
    SELECT 
        p.name,
        cl.name AS club_name,
        g.season,
        SUM(a.goals) AS total_goals
    FROM appearances AS a
    JOIN games AS g ON a.game_id = g.game_id
    JOIN players AS p ON a.player_id = p.player_id
    JOIN club_games cg ON g.game_id = cg.game_id
    JOIN clubs AS cl ON cg.club_id = cl.club_id
    JOIN competitions AS c ON g.competition_id = c.competition_id
    JOIN player_season_counts AS psc ON p.player_id = psc.player_id
    WHERE c.competition_code IN ('bundesliga', 'laliga', 'serie-a', 'ligue-1', 'premier-league')
    GROUP BY p.name, cl.name, g.season
),
moving_avg_goals AS (
    SELECT 
        name,
        club_name,
        season,
        total_goals,
        ROUND(
            AVG(total_goals) OVER (
                PARTITION BY name, club_name
                ORDER BY season
                ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
            )::numeric, 2
        ) AS moving_average_total_goals,
        (total_goals - ROUND(AVG(total_goals) OVER (
                PARTITION BY name, club_name
                ORDER BY season
                ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
            )::numeric, 2)) AS diff
    FROM goals_by_season
)
SELECT 
    name,
    club_name,
    season,
    total_goals,
    moving_average_total_goals,
    diff,
    RANK() OVER (
        ORDER BY diff DESC
    ) AS rank
FROM moving_avg_goals
ORDER BY rank
LIMIT 100;
-- Kylian Mbappe had the steepest increase in goals scored in his 2018/2019 season. He overperformed his 5-year moving average by 21.50 goals.



-- Pattern #3: Which players scored the fastest consecutive hattricks?

WITH appearances_above_2 AS (
    SELECT 
        a.player_name,
        cl.name AS club_name,
        g.season,
        a.date AS first_hattrick_date,
        LEAD(a.date) OVER (PARTITION BY a.player_name, cl.name, g.season ORDER BY a.date) AS second_hattrick_date
    FROM 
        appearances AS a
        JOIN games AS g ON a.game_id = g.game_id
        JOIN club_games cg ON g.game_id = cg.game_id
        JOIN clubs AS cl ON cg.club_id = cl.club_id
        JOIN competitions AS c ON g.competition_id = c.competition_id
    WHERE 
        c.competition_code IN ('bundesliga', 'laliga', 'serie-a', 'ligue-1', 'premier-league')
        AND a.goals > 2
)

SELECT 
    *,
    (second_hattrick_date - first_hattrick_date) AS time_inbetween_hattricks_in_days,
    RANK() OVER (ORDER BY (second_hattrick_date - first_hattrick_date) ASC) AS rank
FROM appearances_above_2
WHERE second_hattrick_date IS NOT NULL
ORDER BY rank ASC
LIMIT 100;
-- There is a total of 4 players who have repeated (at least) a hattrick within only 3 days! Harry Kane has even done it twice.



-- Pattern #4: Which players shot the most total goals in 1 season?

WITH season_goals_ranked AS (
    SELECT 
        a.player_name,
        cl.name AS club_name,
        g.season,
        SUM(a.goals) AS total_goals,
        ROW_NUMBER() OVER (PARTITION BY g.season ORDER BY SUM(a.goals) DESC) AS goals_rank
    FROM 
        appearances AS a
        JOIN games AS g ON a.game_id = g.game_id
        JOIN club_games cg ON g.game_id = cg.game_id
        JOIN clubs AS cl ON cg.club_id = cl.club_id
        JOIN competitions AS c ON g.competition_id = c.competition_id
    WHERE c.competition_code IN ('bundesliga', 'laliga', 'serie-a', 'ligue-1', 'premier-league')
    GROUP BY a.player_name, cl.name, g.season
)
SELECT 
    player_name,
    club_name,
    season,
    total_goals,
    RANK() OVER (ORDER BY total_goals DESC) AS rank
FROM season_goals_ranked
WHERE goals_rank = 1
ORDER BY season;
-- Cristiano Ronaldo has scored 48 goals in the 2014/2015 season!



-- The Sandro Ramirez 2016/2017 season, the Kylian Mbappe 2018/2019 season, the Harry Kane 2017/2018 as well as the Cristiano Ronaldo 2014/2015 season have all been outstanding
-- The following analysis will provide more insights into their respective seasons

-- First, a Table needs to be created that incorporates the players with their respective seasons

DROP TABLE IF EXISTS outstanding_performances;
CREATE TABLE outstanding_performances (
    player_name VARCHAR(100),
    season NUMERIC
);
INSERT INTO outstanding_performances (player_name, season)
VALUES 
    ('Sandro Ramírez', 2016),
    ('Kylian Mbappé', 2018),
    ('Harry Kane', 2017),
    ('Cristiano Ronaldo', 2014);



-- Analysis #1: In which minutes did they score in ther respective leagues and seasons?

SELECT a.player_name,
   	CASE
        WHEN ge.minute <= 15 THEN '0-15 minutes'
        WHEN ge.minute <= 30 THEN '16-30 minutes'
        WHEN ge.minute <= 45 THEN '31-45+ minutes'
        WHEN ge.minute <= 60 THEN '46-60 minutes'
        WHEN ge.minute <= 75 THEN '61-75 minutes'
        ELSE '76-90+ minutes'
    END AS game_brackets,
	SUM(a.goals) AS total_goals
FROM game_events AS ge
JOIN appearances AS a
	ON ge.game_id = a.game_id
	AND ge.player_id = a.player_id
JOIN games AS g
	ON ge.game_id = g.game_id
JOIN outstanding_performances AS o
	ON g.season = o.season
	AND a.player_name = o.player_name
GROUP BY a.player_name, game_brackets
ORDER BY a.player_name, game_brackets ASC;



-- Analysis #2: Where do their respective seasons and the amount of goals scored rank among their other seasons?

SELECT o.player_name, g.season, SUM(a.goals) AS total_goals
FROM appearances AS a
JOIN games AS g
	ON a.game_id = g.game_id
JOIN outstanding_performances AS o
	ON a.player_name = o.player_name
GROUP BY o.player_name, g.season
ORDER BY o.player_name, g.season ASC;



-- Analysis #3: What are the values for the KPIs 'Minutes per Goal' and 'Goals per Match'?

SELECT 
    o.player_name, 
	g.season, 
    CASE WHEN SUM(a.goals) > 0 THEN ROUND((SUM(a.minutes_played) / SUM(a.goals)),2) ELSE NULL END AS minutes_per_goal,
    CASE WHEN COUNT(a.appearance_id) > 0 THEN ROUND((SUM(a.goals) / COUNT(a.appearance_id)),2) ELSE NULL END AS goals_per_match
FROM appearances AS a
JOIN games AS g 
	ON a.game_id = g.game_id
JOIN outstanding_performances AS o 
	ON a.player_name = o.player_name
GROUP BY o.player_name, g.season
ORDER BY o.player_name, g.season ASC;
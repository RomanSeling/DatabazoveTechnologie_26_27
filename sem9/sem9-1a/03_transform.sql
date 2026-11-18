-- Active: 1790162493107@@127.0.0.1@5432@movielens_elt

\set ON_ERROR_STOP on
\encoding UTF8

CREATE SCHEMA IF NOT EXISTS gold;

-- DIM_USER
CREATE TABLE gold.dim_user(
    user_id INT NOT NULL UNIQUE,
    gender CHAR(1) NOT NULL CHECK(gender IN ('M', 'F')),
    zip_code CHAR(10),
    occupation CHAR(50),
    age_group VARCHAR(20) NOT NULL
);

CREATE TABLE gold.dim_movie(
    movie_id INT NOT NULL UNIQUE,
    title VARCHAR(200) NOT NULL,
    release_year INT,
    genre_name VARCHAR(200) NOT NULL  -- všetky žánre budú v 1 riadku
);

-- DIM DATE

CREATE TABLE gold.dim_date(
    date_id INT PRIMARY KEY,
    rated_at DATE NOT NULL UNIQUE,
    day INT NOT NULL,
    month INT NOT NULL,
    year INT NOT NULL,
    day_of_week INT NOT NULL,
    day_name VARCHAR(10) NOT NULL,
    week INT NOT NULL,
    month_name VARCHAR(10) NOT NULL,
    quarter INT NOT NULL
);

-- DIM TIME

CREATE TABLE gold.dim_time(
    time_id INT PRIMARY KEY,
    rated_time TIME NOT NULL UNIQUE,
    hour INT NOT NULL,
    minute INT NOT NULL,
    second INT NOT NULL,
    time_of_day VARCHAR(10) NOT NULL
);

-- FACT_RATING

CREATE TABLE gold.fact_rating(
    rating_id INT PRIMARY KEY,
    user_id INT NOT NULL REFERENCES gold.dim_user(user_id),
    movie_id INT NOT NULL REFERENCES gold.dim_movie(movie_id),
    date_id INT NOT NULL REFERENCES gold.dim_date(date_id),
    time_id INT NOT NULL REFERENCES gold.dim_time(time_id),
    rating NUMERIC(2,1) NOT NULL CHECK (rating BETWEEN 0 AND 5),
    rating_count INT NOT NULL, -- počet hodnotení filmu
    rating_percentage INT NOT NULL -- hodnotenie v percentách
);

-- indexy na cudzie kľúče pretože ich PostGRE nevytvára automaticky

CREATE INDEX ON gold.fact_rating(user_id);
CREATE INDEX ON gold.fact_rating(movie_id);
CREATE INDEX ON gold.fact_rating(date_id);
CREATE INDEX ON gold.fact_rating(time_id);

BEGIN;


TRUNCATE gold.dim_rating, gold.dim_user, gold.dim_movie, gold.dim_date, gold.dim_time;
-- za posledným by bolo RESTART IDENTITY v prípade Auto-Incrementu

--DIM_USER

INSERT INTO gold.dim_user(user_id, gender, zip_code, occupation, age_group)
SELECT u.user_id, u.gender, u.zip_code, COALESCE(o.occupation_name, 'Unknown'), COALESCE(a.age_group_name, 'Unknown')
FROM silver.stg_users u
    LEFT JOIN silver.stg_occupations o ON u.occupation_id = o.occupation_id
    LEFT JOIN silver.stg_age_groups a ON u.age_group_id = a.age_group_id
ORDER BY u.user_id;

--DIM_MOVIE

INSERT INTO gold.dim_movie(movie_id, title, release_year, genre_name)
SELECT m.movie_id, m.title, m.release_year, COALESCE(g.genre_name, 'Unknown')
FROM silver.stg_movies m
    LEFT JOIN (
        SELECT gm.movie_id, STRING_AGG(g.genre_name, ', ' ORDER BY g.genre_name) AS genre_name
        FROM silver.stg_genres_movies gm
        JOIN silver.stg_genres g ON gm.genre_id = g.genre_id
        GROUP BY gm.movie_id
    ) AS g ON m.movie_id = g.movie_id
ORDER BY m.movie_id;

INSERT INTO gold.dim_date(date_id, rated_at, day, month, year, day_of_week, day_name, week, month_name, quarter)
SELECT DISTINCT
    EXTRACT(EPOCH FROM rated_at)::INT AS date_id,
    rated_at::DATE AS rated_at,
    EXTRACT(DAY FROM rated_at) AS day,
    EXTRACT(MONTH FROM rated_at) AS month,
    EXTRACT(YEAR FROM rated_at) AS year,
    EXTRACT(DOW FROM rated_at) AS day_of_week,
    TO_CHAR(rated_at, 'Day') AS day_name,
    EXTRACT(WEEK FROM rated_at) AS week,
    TO_CHAR(rated_at, 'Month') AS month_name,
    EXTRACT(QUARTER FROM rated_at) AS quarter
FROM silver.stg_ratings
ORDER BY rated_at;

INSERT INTO gold.dim_time(time_id, rated_time, hour, minute, second, time_of_day)
SELECT DISTINCT
    EXTRACT(EPOCH FROM rated_at)::INT AS time_id,
    rated_at::TIME AS rated_time,
    EXTRACT(HOUR FROM rated_at) AS hour,
    EXTRACT(MINUTE FROM rated_at) AS minute,
    EXTRACT(SECOND FROM rated_at) AS second,
    CASE
        WHEN EXTRACT(HOUR FROM rated_at) < 12 THEN 'Morning'
        WHEN EXTRACT(HOUR FROM rated_at) < 18 THEN 'Afternoon'
        ELSE 'Evening'
    END AS time_of_day
FROM silver.stg_ratings
ORDER BY rated_time;



COMMIT;

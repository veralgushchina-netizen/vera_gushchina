-- Задача №1 

-- Исключение аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit  
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h
        , PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS
(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND id != 12971 -- аномально высокая цена за м2
        AND id != 8793 -- аномально низкая цена за м2
),
-- Выведем объявления без выбросов, создадим категории по городу и сегменту активности:
category AS  
(  
    SELECT f.*  
        , CASE   
            WHEN f.city_id = '6X8I' THEN 'Санкт-Петербург'  
            ELSE 'ЛенОбл'  
          END AS Регион   
        , CASE   
	        WHEN a.days_exposition <= 30 THEN 'до 1 месяца'  
            WHEN a.days_exposition >= 31 AND a.days_exposition <= 90 THEN 'до 3х месяцев'  
            WHEN a.days_exposition >= 91 AND a.days_exposition <= 180 THEN 'до 6 месяцев'  
            ELSE 'свыше полугода'  
          END AS Сегмент_активности  
        , a.last_price / f.total_area AS price_per_m2 -- рассчитаем цену за 1 м2  
        , CASE  
            WHEN f.rooms = 0 THEN 'студия'  
            WHEN f.rooms = 1 THEN 'комнат 1'  
            WHEN f.rooms = 2 THEN 'комнат 2'  
            WHEN f.rooms = 3 THEN 'комнат 3'  
            ELSE 'комнат 4'  
          END AS количество_комнат  
    FROM real_estate.flats AS f  
    LEFT JOIN real_estate.advertisement AS a USING (id)   
    WHERE f.id IN (SELECT * FROM filtered_id) AND f.type_id = 'F8EM' -- оставим в выборке только тип 'город' 
    -- данные за 2014 и 2019 годы — неполные: за 2014 год данные начинаются с конца ноября, а за 2019 — заканчиваются в мае. 
    -- при изучении годовой динамики параметров, выбираем только полные годы: 2015, 2016, 2017, 2018.
    AND a.first_day_exposition BETWEEN '2015-01-01'::date AND '2018-12-31'::date
    AND a.days_exposition IS NOT NULL  -- уберем пустые значения, тк эти объекты еще не проданы
),  
common AS  
(  
    SELECT  *  
        , COUNT(id) OVER (PARTITION BY Регион) AS количество_объявлений_по_регионам  
        , COUNT(id) OVER (PARTITION BY Регион,  Сегмент_активности, количество_комнат) AS количество_объявлений_по_комнатам  
    FROM category  
)  
SELECT  
        Регион   
        , Сегмент_активности   
        , COUNT(id) AS количество_объявлений  
        , ROUND(COUNT(id)::NUMERIC / количество_объявлений_по_регионам::NUMERIC * 100, 2) AS доля_объявлений  
        , ROUND(SUM(CASE WHEN количество_комнат = 'студия' THEN 1 ELSE 0 END)::NUMERIC  / количество_объявлений_по_регионам::NUMERIC * 100, 2) AS доля_студий  
        , ROUND(SUM(CASE WHEN количество_комнат = 'комнат 1' THEN 1 ELSE 0 END)::NUMERIC  / количество_объявлений_по_регионам::NUMERIC * 100, 2) AS доля_комнат_1  
        , ROUND(SUM(CASE WHEN количество_комнат = 'комнат 2' THEN 1 ELSE 0 END)::NUMERIC / количество_объявлений_по_регионам::NUMERIC * 100, 2) AS доля_комнат_2  
        , ROUND(SUM(CASE WHEN количество_комнат = 'комнат 3' THEN 1 ELSE 0 END)::NUMERIC  / количество_объявлений_по_регионам::NUMERIC * 100, 2) AS доля_комнат_3  
        , ROUND(SUM(CASE WHEN количество_комнат = 'комнат 4' THEN 1 ELSE 0 END)::NUMERIC  / количество_объявлений_по_регионам::NUMERIC * 100, 2) AS доля_комнат_4  
        , ROUND(AVG(price_per_m2)::NUMERIC, 0) AS avg_стоимость_м2  
        , ROUND(AVG(total_area)::NUMERIC, 2) AS avg_площадь  
        , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS медиана_комнат  
        , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony) AS медиана_балконов  
        , PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floors_total) AS этажность_дома  
        , PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floor) AS медиана_этажа  
        , PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY parks_around3000) AS медиана_парков 
        , PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ponds_around3000) AS медиана_водоемов 
FROM common  
GROUP BY Регион, Сегмент_активности, количество_объявлений_по_регионам  
ORDER BY Регион DESC, Сегмент_активности;  


-- Задача №2
-- 2.1 Проведем исследование месяцев публикаций объявлений
-- Исключение аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
SET lc_time = 'en_US';
WITH limits AS (
    SELECT  
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit  
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h
        , PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS
(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND id != 12971 -- аномально высокая цена за м2
        AND id != 8793 -- аномально низкая цена за м2
),
date_information AS  
(  
    SELECT f.id AS id  
        , a.first_day_exposition AS дата_подачи_объявления  
        , a.last_price / f.total_area AS price_per_m2 -- рассчитаем цену за 1 м2  
        , f.total_area   
    FROM real_estate.flats AS f  
    LEFT JOIN real_estate.advertisement AS a USING (id)  
    WHERE f.id IN (SELECT * FROM filtered_id) 
    -- данные за 2014 и 2019 годы — неполные: за 2014 год данные начинаются с конца ноября, а за 2019 — заканчиваются в мае. 
    -- при изучении годовой динамики параметров, выбираем только полные годы: 2015, 2016, 2017, 2018.
    AND a.first_day_exposition BETWEEN '2015-01-01'::date AND '2018-12-31'::date
    AND f.type_id = 'F8EM' -- оставляем только города, та как именно недвижимость городов определит основные статистические показатели
),  
month_information AS   
(  
    SELECT   
        id   
        , TO_CHAR(дата_подачи_объявления, 'TMmonth') AS месяц_подачи_объявления  
        , price_per_m2  
        , total_area   
    FROM date_information  
)
    SELECT   
        RANK() OVER (ORDER BY COUNT(id) DESC) AS ранг 
    	, месяц_подачи_объявления  
        , COUNT(id) AS количество 
        , ROUND(COUNT(id) / SUM(COUNT(id)) OVER () * 100, 2) AS доля  
        , ROUND (AVG(price_per_m2)::NUMERIC, 0) AS avg_стоимость_м2  
        , ROUND (AVG(total_area)::NUMERIC, 2) AS avg_площадь  
    FROM month_information  
    GROUP BY месяц_подачи_объявления;  
    
    
-- 2.2 Проведем исследование месяцев снятия объявлений
-- Исключение аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
SET lc_time = 'en_US';
WITH limits AS (
    SELECT  
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit  
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h
        , PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS
(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND id != 12971 -- аномально высокая цена за м2
        AND id != 8793 -- аномально низкая цена за м2
),
date_information AS  
(  
    SELECT f.id AS id  
        , a.first_day_exposition::date + a.days_exposition::integer AS дата_снятия_объявления  
        , a.last_price / f.total_area AS price_per_m2 -- рассчитаем цену за 1 м2  
        , f.total_area   
    FROM real_estate.flats AS f  
    LEFT JOIN real_estate.advertisement AS a USING (id)  
    WHERE f.id IN (SELECT * FROM filtered_id) 
    -- данные за 2014 и 2019 годы — неполные: за 2014 год данные начинаются с конца ноября, а за 2019 — заканчиваются в мае. 
    -- при изучении годовой динамики параметров, выбираем только полные годы: 2015, 2016, 2017, 2018.
    AND a.first_day_exposition BETWEEN '2015-01-01'::date AND '2018-12-31'::date
    AND f.type_id = 'F8EM' -- оставляем только города, та как именно недвижимость городов определит основные статистические показатели
    AND a.days_exposition IS NOT NULL -- убираем объявления, которые не сняты с публикации
),  
month_information AS 
(  
    SELECT   
        id   
        , TO_CHAR(дата_снятия_объявления, 'TMmonth') AS месяц_снятия_объявления
        , price_per_m2  
        , total_area   
    FROM date_information  
)
    SELECT   
        RANK() OVER (ORDER BY COUNT(*) DESC) AS ранг
        , месяц_снятия_объявления 
        , COUNT(*) AS количество
        , ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS доля  
        , ROUND (AVG(price_per_m2)::NUMERIC, 0) AS avg_стоимость_м2 
        , ROUND( AVG(total_area)::NUMERIC, 2) AS avg_площадь    
    FROM month_information  
    GROUP BY месяц_снятия_объявления;  
    
 

-- Задача №3

WITH limits AS (
    SELECT  
          PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit  
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit
        , PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h
        , PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS
(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND id != 12971 -- аномально высокая цена за м2
        AND id != 8793 -- аномально низкая цена за м2
        AND city_id != '6X8I' -- исключаем Санкт-Петербург
)
SELECT 
		 c.city
		, RANK () OVER (ORDER BY COUNt (f.id) DESC) AS RANK
		, COUNT (a.first_day_exposition) AS количество_объявлений
		, ROUND (COUNT (a.days_exposition)/COUNT (a.first_day_exposition)::NUMERIC , 2) AS доля_снятых_объявлений
		, ROUND (AVG (a.last_price/f.total_area)::numeric , 0) AS цена_м2
		, ROUND (AVG (f.total_area)::NUMERIC ,0) AS avg_площадь
		, ROUND (AVG (a.days_exposition)::NUMERIC , 0) AS avg_срок_продажи
		, PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY f.rooms)  AS медиана_комнат
		, PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY f.balcony) AS медиана_балконов
		, PERCENTILE_DISC (0.5) WITHIN GROUP (ORDER BY f.floors_total) AS этажность_дома
		, PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY f.floor) AS медиана_этажа
FROM real_estate.flats AS f
LEFT JOIN real_estate.advertisement AS a USING (id)
LEFT JOIN real_estate.city AS c USING (city_id)
WHERE f.id IN (SELECT * FROM filtered_id) AND a.first_day_exposition BETWEEN '2015-01-01'::date AND '2018-12-31'::date
GROUP BY  c.city 
ORDER BY RANK
LIMIT 15;












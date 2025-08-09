/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Агафонова Ольга
 * Дата: 28.02.2025г.
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем объявления без выбросов:
norm_id AS(
     SELECT *
     FROM real_estate.flats 
     WHERE id IN(SELECT * FROM filtered_id)
     ),
-- Разделим объявления на группы по регионам и срокам активности :
region_active AS(
     SELECT *,      
      CASE
        WHEN c.city='Санкт-Петербург'
        THEN 'Санкт-Петербург'
        WHEN c.city<>'Санкт-Петербург'
        THEN 'ЛенОбл'
      END AS region, 
        CASE 
       	  WHEN days_exposition<=30
       	  THEN 'месяц'
       	  WHEN days_exposition>30 AND days_exposition<=90
       	  THEN 'три месяца'
          WHEN days_exposition>90 AND days_exposition<=180
       	  THEN 'шесть месяцев'
       	  WHEN days_exposition>180
       	  THEN 'шесть месяцев и более'
       	  ELSE 'other'
        END AS activnost_id
   FROM norm_id AS n
   LEFT JOIN real_estate.city AS c USING(city_id)      
   LEFT JOIN real_estate.advertisement AS a USING(id)
   WHERE first_day_exposition >= '01.01.2015' AND first_day_exposition <= '31.12.2018'
),
-- Рассчитаем стоимость квадратного метра, учитывая населенный пункт только "город" :
parametry AS(
   SELECT *,        
       last_price/total_area AS one_kvmetr
   FROM region_active AS r
   JOIN real_estate.type AS t USING(type_id)
   WHERE type='город'
),
-- Выведем ряд показателей для более детального исследования рынка недвижимлсти в данном регионе:
data_kvart AS(
   SELECT 
     region AS Region,
     activnost_id AS Activity_segment,
     COUNT(id) AS Cnt_ads,
     ROUND(AVG(one_kvmetr::numeric), 0) AS Avg_kvm,
     ROUND(AVG(total_area::numeric), 0) AS Avg_area,
     PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY rooms) AS Perc_rooms,
     PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY balcony) AS Perc_balcony,
     PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY floor) AS Perc_floors,
     PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY floors_total) AS Perc_fl_total,
     ROUND(AVG(ceiling_height::numeric), 1) AS Avg_hight,
     ROUND(AVG(airports_nearest::numeric)/1000, 0) AS Avg_airports,
     PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY parks_around3000) AS Perc_park,
     PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY ponds_around3000) AS Perc_ponds
   FROM parametry
   GROUP BY region, activnost_id
   ORDER BY region DESC
)
--Рассчитаем долю объявлений относительно региона и выведем основной запрос:
SELECT Region,
       Activity_segment,
       Cnt_ads,
       (SUM(Cnt_ads) OVER(PARTITION BY Region)) AS sum_ads,
       ROUND((Cnt_ads::numeric/(SUM(Cnt_ads) OVER(PARTITION BY Region ORDER BY Activity_segment)))*100, 0) AS dolya,
       Avg_kvm,
       Avg_area,
       Perc_rooms,
       Perc_balcony,
       Perc_floors,
       Perc_fl_total,
       Avg_hight,
       Avg_airports,
       Perc_park,
       Perc_ponds
FROM data_kvart;

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

1 ЗАПРОС (информация по опубликованным объявлениям):

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем объявления без выбросов и по типу "город":
norm_id AS(
     SELECT *
     FROM real_estate.flats
     JOIN real_estate.type AS t USING(type_id)
     WHERE type='город' AND id IN(SELECT * FROM filtered_id)
 ),
--Вычислим ср.стоим-ть кв.метра и среднюю площадь жилья, 
-- определим активность публикаций объявлений по месяам: 
opubl_ads AS(
    SELECT a.id AS id,
       a.last_price/n.total_area AS avg_one_kvmetr,
       AVG(n.total_area) AS avg_area,  
       EXTRACT(MONTH FROM a.first_day_exposition::timestamp) AS month
    FROM norm_id AS n  
    JOIN real_estate.advertisement AS a USING(id)
    JOIN real_estate.type AS t USING(type_id)
    GROUP BY a.id, a.last_price, n.total_area, a.first_day_exposition 
)
--Выведем все данные по опубликованным объявлениям в основном запросе :
SELECT 
      CASE 
     	WHEN month=1
     	THEN 'Jenuary'
     	WHEN month=2
     	THEN 'February'
     	WHEN month=3
     	THEN 'March'
     	WHEN month=4
     	THEN 'April'
     	WHEN month=5
     	THEN 'May'
     	WHEN month=6
     	THEN 'June'
     	WHEN month=7
     	THEN 'July'
     	WHEN month=8
     	THEN 'August'
     	WHEN month=9
     	THEN 'September'
     	WHEN month=10
     	THEN 'October'
     	WHEN month=11
     	THEN 'November'
     	WHEN month=12
     	THEN 'December'
     END AS month,
     COUNT(id) AS opubl_ads,
     ROUND(AVG(avg_one_kvmetr::numeric), 0) AS avg_kvm,
     ROUND(AVG(avg_area::numeric), 0) AS avg_tot_area
FROM opubl_ads
GROUP BY month
ORDER BY opubl_ads DESC;

2 ЗАПРОС (информация по снятым объявлениям):

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем объявления без выбросов и по типу "город":
norm_id AS(
     SELECT *
     FROM real_estate.flats
     JOIN real_estate.type AS t USING(type_id)
     WHERE type='город' AND id IN(SELECT * FROM filtered_id)
 ),
--Вычислим ср.ст-ть кв.метра и среднюю площадь жилья, 
-- по снятым объявлениям определим активность продаж жилья относительно времени года : 
zakr_ads AS(
    SELECT a.id AS id,
       a.last_price/n.total_area AS avg_one_kvmetr,
       AVG(n.total_area) AS avg_area,  
       EXTRACT(MONTH FROM (a.first_day_exposition+a.days_exposition::integer)::timestamp) AS month
    FROM norm_id AS n  
    JOIN real_estate.advertisement AS a USING(id)
    JOIN real_estate.type AS t USING(type_id)
    WHERE a.days_exposition IS NOT NULL
    GROUP BY a.id, a.last_price, n.total_area, a.first_day_exposition 
)
--Выведем все данные по снятым объявлениям в основном запросе :
SELECT 
      CASE 
     	WHEN month=1
     	THEN 'Jenuary'
     	WHEN month=2
     	THEN 'February'
     	WHEN month=3
     	THEN 'March'
     	WHEN month=4
     	THEN 'April'
     	WHEN month=5
     	THEN 'May'
     	WHEN month=6
     	THEN 'June'
     	WHEN month=7
     	THEN 'July'
     	WHEN month=8
     	THEN 'August'
     	WHEN month=9
     	THEN 'September'
     	WHEN month=10
     	THEN 'October'
     	WHEN month=11
     	THEN 'November'
     	WHEN month=12
     	THEN 'December'
     END AS month,
     COUNT(id) AS zakr_ads,
     ROUND(AVG(avg_one_kvmetr::numeric), 0) AS avg_kvm,
     ROUND(AVG(avg_area::numeric), 0) AS avg_tot_area
FROM zakr_ads
GROUP BY month
ORDER BY zakr_ads DESC;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Выведем объявления без выбросов и только по нас.пунктам Ленинградской области:
norm_id AS(
     SELECT *
     FROM real_estate.flats 
     LEFT JOIN real_estate.city AS c USING(city_id)
     WHERE c.city<>'Санкт-Петербург' AND id IN(SELECT * FROM filtered_id)
     )
-- Сформируем основную выборку по населенным пунктам Лен.области и разделим объявления на 4 категории 
-- по ср.значению дней активности, определим значения всех опубл-х и снятых объявлений, 
-- долю снятых объяв-й, длительность продаж, ср. стоим-ть кв.метра и среднюю площадь квартир :  
SELECT  city AS nazvanie,
        COUNT(id) AS vse_obyav,
        COUNT(days_exposition) AS zakr_obv,
        ROUND((((COUNT(days_exposition)/COUNT(id)::real)*100)::numeric), 0) AS dolya_zakr,
        (ROUND(AVG(a.days_exposition)::numeric, 0)) AS dlitelnost,
        NTILE(4) OVER(ORDER BY (ROUND(AVG(a.days_exposition)::numeric, 0))) AS grupp, 
        ROUND(AVG(last_price/total_area)::numeric, 0) AS avg_kvm,
        ROUND(AVG(total_area)::numeric, 0) AS avg_area 
FROM norm_id 
LEFT JOIN real_estate.advertisement AS a USING(id)
GROUP BY city
ORDER BY vse_obyav DESC
LIMIT 15;
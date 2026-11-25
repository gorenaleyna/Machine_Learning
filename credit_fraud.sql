-- In this project our main aim is to look at the two different tables
-- sometimes we might need to (probably we will) union those tables. 

USE creditfraud;

SELECT * 
FROM application_record;

-- This table shows us the person who had applied for the credit card and their background

SELECT * 
FROM credit_record;

-- This one shows the loans, and STATUS column shows us if the loan is paid for this month is indicated as C,
-- If its due it is indicated as 1,2,3,4 ; as the days of overdue increases the number increases too. 
-- X means there is no loans for that month.

SELECT 'application_record' as table_name, COUNT(*) AS total_entries FROM application_record
UNION ALL
SELECT 'credit_record' as table_name, COUNT(*) AS total_entries FROM credit_record;

-- When I look at the output I see that rows number is not equal for both tables. How can we solve this problem? 
-- Best way is to look how many distinct values in both datasets together. 

SELECT
(SELECT COUNT(DISTINCT ID ) FROM application_record) AS unique_apps,
(SELECT COUNT(DISTINCT ID) FROM credit_record) AS unique_credit,
(SELECT COUNT(DISTINCT a.ID)
FROM application_record a
JOIN credit_record c on a.ID = c.ID) as matching_ids;

-- When I upload the files unfortunately sql wasn't able to get all of the data so
-- I imported data from python jupyter notebook. I will share a notebook about it too.
-- Now I will make a default risk tag for some applicants who has bad credit score.
-- However there is hundred thousands data in credit score so I need to decrease the number of entries by feature engineering the
-- customer's total months in the database, longest period of his late payment, the month that she didn't paid late.

SELECT
	a.ID,
    a.AMT_INCOME_TOTAL,
    a.CODE_GENDER,
    a.FLAG_OWN_CAR,
    COUNT(c.MONTHS_BALANCE) as total_recorded_months,
    MIN(c.MONTHS_BALANCE) as account_history_lenght,
    MAX(CASE WHEN c.STATUS IN ('2','3','4','5') THEN 1 ELSE 0 END) as is_high_risk
FROM application_record a
LEFT JOIN credit_record c ON a.ID = c.ID
GROUP BY a.ID, a.AMT_INCOME_TOTAL,a.CODE_GENDER,a.FLAG_OWN_CAR;


-- lets see the high risk customers
SELECT COUNT(DISTINCT ID) AS is_high_risk
FROM credit_record
WHERE STATUS IN ('2','3','4','5');

-- I see here that we have really little high risk customers, the number is 667.
-- This causes that we have lots of great cutomers and it is hard to find. Now we will turn the application_record 
-- to be proccessable by python for machine learning.

SELECT
	a.ID,
    a.CODE_GENDER,
    a.FLAG_OWN_CAR,
    a.FLAG_OWN_REALTY,
    a.CNT_CHILDREN,
    a.AMT_INCOME_TOTAL,
    a.NAME_INCOME_TYPE,
    a.NAME_EDUCATION_TYPE,
    a.NAME_FAMILY_STATUS,
    a.NAME_HOUSING_TYPE,
    MAX(CASE WHEN c.STATUS IN ('2','3','4','5') THEN 1 ELSE 0 END) AS is_high_risk
FROM application_record a 
INNER JOIN credit_record c ON a.ID=c.ID
GROUP BY
	a.ID, 
    a.CODE_GENDER, 
    a.FLAG_OWN_CAR, 
    a.FLAG_OWN_REALTY, 
    a.CNT_CHILDREN, 
    a.AMT_INCOME_TOTAL, 
    a.NAME_INCOME_TYPE, 
    a.NAME_EDUCATION_TYPE, 
    a.NAME_FAMILY_STATUS, 
    a.NAME_HOUSING_TYPE;
	
-- We are using INNER JOIN because we only want customerswho appear in both tables.

-- Cheking high risk rate by ownership

SELECT
	a.FLAG_OWN_CAR,
    COUNT(DISTINCT a.ID) AS total_customers,
    SUM(CASE WHEN risk.max_status IN ('2','3','4','5') THEN 1 ELSE 0 END ) AS high_risk_customers
FROM application_record a
INNER JOIN (
	SELECT ID, MAX(CASE WHEN STATUS IN ('2','3','4','5') THEN 1 ELSE 0 END) AS max_status
    FROM credit_record 
    GROUP BY ID
) risk ON a.ID = risk.ID
GROUP BY a.FLAG_OWN_CAR;

 -- actually both of the side which have car or not are neither high risk customers. May be we should
 -- look for more demographic features.
 
 -- we will look at first the employment type
 
 WITH customer_risk AS(
	SELECT 
		ID,
        MAX(CASE WHEN STATUS IN ('2','3','4','5') THEN 1 ELSE 0 END) AS is_high_risk
        FROM credit_record
        GROUP BY ID
 )
 SELECT 
	a.NAME_INCOME_TYPE,
    COUNT(*) AS total_customers,
    SUM(r.is_high_risk) AS high_risk_customers,
    ROUND(SUM(r.is_high_risk)*100.00 / COUNT(*),2) AS high_risk_pct
FROM application_record a
INNER JOIN customer_risk r ON a.ID = r.ID
GROUP BY a.NAME_INCOME_TYPE
ORDER BY high_risk_pct DESC;

-- We can say that pensioners are the highest rsk customers with 2.11 high_risk percentage and when you look at the working 
-- you can see that totally there iss 18,819 customers and only 306 of them are high risk customers so based on this
-- ratio its actually pretty good.

-- income and age segmentation

WITH customer_risk AS (
	SELECT
		ID,
        MAX(CASE WHEN STATUS IN('2','3','4','5',2,3,4,5) THEN 1 ELSE 0 END) AS is_high_risk
        FROM credit_record
        GROUP BY ID
),
demo_prep AS(
	SELECT
		a.ID,
        a.AMT_INCOME_TOTAL,
        FLOOR(ABS(a.DAYS_BIRTH)/365.25) AS age_years,
        r.is_high_risk
	FROM application_record a
    INNER JOIN customer_risk r ON a.ID = r.ID
)
SELECT 
	CASE 
		WHEN age_years < 25 THEN '18-24'
		WHEN age_years < 35 THEN '25-34'
		WHEN age_years < 45 THEN '35-44'
		WHEN age_years < 55 THEN '45-54'
		ELSE '55+'
	END AS age_group,
    COUNT(*) AS total_customers,
    SUM(is_high_risk) AS high_risk_customers,
    ROUND(SUM(is_high_risk)*100 / COUNT(*),2) AS high_risk_pct,
    ROUND(AVG(AMT_INCOME_TOTAL),0) AS avg_income
FROM demo_prep
GROUP BY age_group
ORDER BY age_group;

-- As we can see here that highest income are in 45-54 but its high risk percentage is higher the reason for that is
-- as I guess because they are the ones are close to be retired or has been cut hours/working less shifts etc..
-- so they have savings but now they do not make so much money as they do before, ir is actually an economic theory and we see that
-- as the age increases after a point the average salary decreases. So 35-44 has slighly lower however also their risk is lower.

DROP TABLE IF EXISTS master_credit_risk;

CREATE TABLE master_credit_risk AS
WITH credit_summary AS (
    SELECT 
        ID,
        COUNT(*) AS total_recorded_months,
        MAX(CASE WHEN STATUS IN ('2', '3', '4', '5', 2, 3, 4, 5) THEN 1 ELSE 0 END) AS is_high_risk
    FROM credit_record
    GROUP BY ID
)
SELECT 
    a.ID,
    a.CODE_GENDER,
    a.FLAG_OWN_CAR,
    a.FLAG_OWN_REALTY,
    a.CNT_CHILDREN,
    a.CNT_FAM_MEMBERS,
    a.AMT_INCOME_TOTAL,
    a.NAME_INCOME_TYPE,
    a.NAME_EDUCATION_TYPE,
    a.NAME_FAMILY_STATUS,
    a.NAME_HOUSING_TYPE,
    FLOOR(ABS(a.DAYS_BIRTH) / 365.25) AS age_years,
    CASE 
        WHEN FLOOR(ABS(a.DAYS_BIRTH) / 365.25) < 25 THEN '18-24'
        WHEN FLOOR(ABS(a.DAYS_BIRTH) / 365.25) < 35 THEN '25-34'
        WHEN FLOOR(ABS(a.DAYS_BIRTH) / 365.25) < 45 THEN '35-44'
        WHEN FLOOR(ABS(a.DAYS_BIRTH) / 365.25) < 55 THEN '45-54'
        ELSE '55+'
    END AS age_group,
    CASE 
        WHEN a.DAYS_EMPLOYED < 0 THEN ROUND(ABS(a.DAYS_EMPLOYED) / 365.25, 1)
        ELSE 0 
    END AS employment_years,
    CASE 
        WHEN a.DAYS_EMPLOYED < 0 THEN 1 
        ELSE 0 
    END AS is_currently_employed,
    c.total_recorded_months,
    c.is_high_risk
FROM application_record a
INNER JOIN credit_summary c ON a.ID = c.ID;



SELECT * 
FROM master_credit_risk;







--creating new table with primary key to insert club member information data into
DROP TABLE IF EXISTS cminfo
CREATE TABLE cminfo(
	member_id INT IDENTITY(1,1) PRIMARY KEY,
	full_name VARCHAR(100),
	age INT,
	martial_status VARCHAR(50),
	email VARCHAR(150),
	phone VARCHAR(50),
	full_address VARCHAR(300),
	job_title VARCHAR(100),
	membership_date DATE
);

--inserting club member information data into created table
INSERT INTO cminfo(
			full_name,
			age,
			martial_status,
			email,
			phone,
			full_address,
			job_title,
			membership_date)
SELECT full_name, age, martial_status, email, phone, full_address, job_title, membership_date
FROM club_member_info

--removing special characters and trimming whitespaces from full_name
UPDATE cminfo
SET full_name =	LOWER(
			TRIM(
			REPLACE(
			TRANSLATE(full_name, '?#@+$^&*"~', REPLICATE('-',10)), '-', '')
			)
			)

--selecting transformed and cleansed columns into new table dim_club_member
SELECT member_id,
	   --splitting full_name column into first_name and last_name
			SUBSTRING(
				full_name, 1, CHARINDEX(' ', full_name) - 1) 
	   AS first_name,
			SUBSTRING(
				full_name, CHARINDEX(' ', full_name) + 1, LEN(full_name) - CHARINDEX(' ', full_name)) 
	   AS last_name,
	   --some rows have age as 3-digit integer
	   --coverting blanks into null, appropriating data range and trimming whitespace
			CASE 
			WHEN LEN(CAST(age AS VARCHAR)) = 0 THEN NULL
			WHEN LEN(CAST(age AS VARCHAR)) > 2 THEN SUBSTRING(CAST(age AS VARCHAR), 1, 2)
			ELSE TRIM(CAST(age AS VARCHAR))
			END 
	   AS age,
	   --converting blanks into null and trimming whitespace
			CASE 
			WHEN LEN(TRIM(martial_status)) = 0 THEN NULL
			ELSE TRIM(martial_status)
			END 
	   AS marital_status,
	   --trimming whitespace and spaces within email id
			REPLACE(TRIM(email), ' ', '')
	   AS email_id,
	   --some rows have invalid contact numbers i.e less than 12 digits
	   --converting blanks and invalid contact numbers into nulls and trimming whitespace 
			CASE
			WHEN TRIM(phone) = '' THEN NULL
			WHEN LEN(CAST(phone AS VARCHAR)) < 12 THEN NULL
			ELSE TRIM(phone)
			END
	   AS contact_no	
INTO dim_club_member
FROM cminfo

--adding relevant columns to table for inserting split values from full_address
ALTER TABLE dim_club_member
ADD street_address NVARCHAR(250),
    city NVARCHAR(250),
    state NVARCHAR(100)

--splitting full_address column into street_address, city and state
--pivoting split results corresponding to each row
--updating street_address, city and state column values on table dim_club_member
WITH address_cte AS 
(SELECT member_id, TRIM(VALUE) AS value,
ROW_NUMBER() OVER(PARTITION BY member_id ORDER BY member_id) AS row_num
FROM cminfo
CROSS APPLY STRING_SPLIT(full_address, ',')
),
address_cte2 AS
(
SELECT member_id,
	   [1] AS street_address,  
	   [2] AS city,
	   [3] AS state
FROM address_cte
PIVOT (MAX(value) FOR row_num IN ([1], [2], [3])) AS pvot)
UPDATE dim_club_member
SET dim_club_member.street_address = address_cte2.street_address,
    dim_club_member.city = address_cte2.city,
    dim_club_member.state = address_cte2.state
FROM dim_club_member
INNER JOIN address_cte2
ON dim_club_member.member_id = address_cte2.member_id

--adding job_title column to table dim_club_member
ALTER TABLE dim_club_member
ADD job_title NVARCHAR(100)

--updating job_title column values as only job titles without job levels i.e removing ('i','ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii') from job title
UPDATE dim_club_member
SET job_title = CASE
		WHEN LOWER(TRIM(RIGHT(cminfo.job_title, CHARINDEX(' ', REVERSE(cminfo.job_title))))) IN ('i','ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii')
			THEN TRIM(LOWER(TRIM(RIGHT(cminfo.job_title, CHARINDEX(' ', REVERSE(cminfo.job_title))))) FROM cminfo.job_title)
		ELSE TRIM(cminfo.job_title)
		END
FROM cminfo
INNER JOIN dim_club_member
ON dim_club_member.member_id = cminfo.member_id

--adding relevant column for job title levels
ALTER TABLE dim_club_member
ADD designation_level INT

--replacing designation levels in roman numbers with integers
--updating designation_level values
WITH cte AS
(
SELECT member_id, job_title, 
	   LOWER(TRIM(RIGHT(job_title, CHARINDEX(' ', REVERSE(job_title))))) AS level
FROM cminfo
)
UPDATE dim_club_member
SET designation_level = CASE
			WHEN LOWER(TRIM(RIGHT(cte.job_title, CHARINDEX(' ', REVERSE(cte.job_title))))) IN ('i','ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii')
				THEN CASE
				     WHEN level = 'i' THEN REPLACE(cte.job_title, cte.job_title, 1)
				     WHEN level = 'ii' THEN REPLACE(cte.job_title, cte.job_title, 2)
				     WHEN level = 'iii' THEN REPLACE(cte.job_title, cte.job_title, 3)
				     WHEN level = 'iv' THEN REPLACE(cte.job_title, cte.job_title, 4)
				     WHEN level = 'v' THEN REPLACE(cte.job_title, cte.job_title, 5)
				     WHEN level = 'vi' THEN REPLACE(cte.job_title, cte.job_title, 6)
				     WHEN level = 'vii' THEN REPLACE(cte.job_title, cte.job_title, 7)
				     WHEN level = 'viii' THEN REPLACE(cte.job_title, cte.job_title, 8)
				     ELSE NULL
				     END
			 ELSE NULL
			 END
FROM cte
INNER JOIN dim_club_member
ON cte.member_id = dim_club_member.member_id

--adding relevant column to table 
ALTER TABLE dim_club_member
ADD membership_date DATE

--replacing 1900s years with 2000s years since all memberships occurred in 2000s
--updating membership_dates values accordingly
UPDATE dim_club_member
SET membership_date = CASE
		      WHEN LEFT(TRIM(CAST(YEAR(cminfo.membership_date) AS NVARCHAR)), 2) != 20 THEN STUFF(cminfo.membership_date, 1, 2, 20)
		      ELSE TRIM(CAST(cminfo.membership_date AS NVARCHAR))
		      END
FROM dim_club_member
INNER JOIN cminfo
ON dim_club_member.member_id = cminfo.member_id

--unique email ids required for membership; checking for duplicate member entries
SELECT *
FROM dim_club_member
WHERE email_id IN
(SELECT email_id
FROM dim_club_member
GROUP BY email_id
HAVING COUNT(email_id) > 1)

--removing duplicate member entries based on duplicate email ids, keeping only the latest among duplicate entries
DELETE a
FROM dim_club_member AS a
JOIN dim_club_member AS b
ON a.email_id = b.email_id
WHERE a.member_id < b.member_id

--checking for incorrect spellings; leads to dual values for same attribute 
SELECT DISTINCT marital_status
FROM dim_club_member

--replacing inconsistencies (incorrect spelling) 
UPDATE dim_club_member
SET marital_status = 'divorced'
WHERE marital_status = 'divored'

--transformed and cleansed data
SELECT *
FROM dim_club_member


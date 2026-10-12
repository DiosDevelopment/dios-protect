-- ESX Legacy default job schema. Import once before starting dios_protect.
-- If you rename jobs in config.lua, rename them here too. Existing jobs are preserved.
INSERT IGNORE INTO jobs (name,label) VALUES ('president','President'),('secretservice','Secret Service');
INSERT INTO job_grades (job_name,grade,name,label,salary,skin_male,skin_female)
SELECT 'president',0,'president','President',300,'{}','{}'
WHERE NOT EXISTS (SELECT 1 FROM job_grades WHERE job_name='president' AND grade=0);
INSERT INTO job_grades (job_name,grade,name,label,salary,skin_male,skin_female)
SELECT 'secretservice',0,'agent','Protection Agent',150,'{}','{}'
WHERE NOT EXISTS (SELECT 1 FROM job_grades WHERE job_name='secretservice' AND grade=0);
INSERT INTO job_grades (job_name,grade,name,label,salary,skin_male,skin_female)
SELECT 'secretservice',1,'commander','Detail Commander',200,'{}','{}'
WHERE NOT EXISTS (SELECT 1 FROM job_grades WHERE job_name='secretservice' AND grade=1);

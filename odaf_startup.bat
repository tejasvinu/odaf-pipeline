@echo off
setlocal enabledelayedexpansion

echo =============================================
echo ODAF Pipeline - Windows Startup Script
echo =============================================
echo.

:: Create log file
set LOG_FILE=%~dp0odaf_startup_win.log
echo Starting ODAF Pipeline at %date% %time% > %LOG_FILE%

:: Check if Docker is running
echo Checking if Docker is running...
docker info > nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Docker is not running. Please start Docker Desktop first. >> %LOG_FILE%
    echo ERROR: Docker is not running. Please start Docker Desktop first.
    pause
    exit /b 1
)
echo Docker is running. >> %LOG_FILE%
echo Docker is running.

:: Setup volume directories
echo Setting up volume directories...
mkdir volumes\prometheus_data 2>nul
mkdir volumes\grafana_data 2>nul
mkdir volumes\airflow_logs 2>nul
mkdir volumes\airflow_config 2>nul
mkdir volumes\spark 2>nul
mkdir volumes\spark-worker-1 2>nul
mkdir volumes\zookeeper_data 2>nul
mkdir volumes\kafka_data 2>nul
mkdir volumes\cassandra_data 2>nul
mkdir volumes\minio_data 2>nul
mkdir volumes\postgres_data 2>nul
mkdir volumes\jupyter_data 2>nul
mkdir volumes\data 2>nul
echo Volume directories created. >> %LOG_FILE%
echo Volume directories created.

:: Fix line endings in script files
echo Fixing line endings in script files...
cd /d %~dp0
if exist "airflow-entrypoint.sh" (
    echo Fixing line endings for airflow-entrypoint.sh
    powershell -Command "(Get-Content -Raw 'airflow-entrypoint.sh') -replace '\r\n', '\n' | Set-Content -NoNewline 'airflow-entrypoint.sh'"
)
if exist "verify_environment.sh" (
    echo Fixing line endings for verify_environment.sh
    powershell -Command "(Get-Content -Raw 'verify_environment.sh') -replace '\r\n', '\n' | Set-Content -NoNewline 'verify_environment.sh'"
)
if exist "setup_permissions.sh" (
    echo Fixing line endings for setup_permissions.sh
    powershell -Command "(Get-Content -Raw 'setup_permissions.sh') -replace '\r\n', '\n' | Set-Content -NoNewline 'setup_permissions.sh'"
)
if exist "fix_permissions.sh" (
    echo Fixing line endings for fix_permissions.sh
    powershell -Command "(Get-Content -Raw 'fix_permissions.sh') -replace '\r\n', '\n' | Set-Content -NoNewline 'fix_permissions.sh'"
)
echo Line endings fixed. >> %LOG_FILE%
echo Line endings fixed.

:: Check if containers are running and handle accordingly
echo Checking for running containers...
docker-compose ps -q > nul
if %errorlevel% equ 0 (
    echo Some containers are already running.
    set /p choice=Do you want to restart all containers? (y/n): 
    if /i "!choice!"=="y" (
        echo Stopping all containers...
        docker-compose down
        
        echo Starting all containers...
        docker-compose up -d
    ) else (
        echo Skipping container restart.
    )
) else (
    echo Starting all containers...
    docker-compose up -d
)

echo Waiting 30 seconds for containers to initialize...
timeout /t 30 /nobreak > nul

:: Fix the Airflow issue by reinstalling Apache Airflow in the container
echo Fixing Airflow installation...
echo Fixing Airflow installation... >> %LOG_FILE%
docker-compose exec -T airflow bash -c "pip install --force-reinstall apache-airflow==2.5.0 && pip install --force-reinstall apache-airflow-providers-apache-spark==4.1.0"
echo Airflow reinstallation completed. >> %LOG_FILE%
echo Airflow reinstallation completed.

echo Fixing permissions in containers...
docker-compose exec -T prometheus sh -c "chmod -R 777 /prometheus" >> %LOG_FILE% 2>&1
docker-compose exec -T grafana sh -c "chmod -R 777 /var/lib/grafana" >> %LOG_FILE% 2>&1
docker-compose exec -T airflow sh -c "mkdir -p /opt/airflow/logs/scheduler /opt/airflow/logs/dag_processor && chmod -R 777 /opt/airflow" >> %LOG_FILE% 2>&1

echo Restarting containers...
docker-compose restart airflow >> %LOG_FILE% 2>&1
docker-compose restart airflow-scheduler >> %LOG_FILE% 2>&1
docker-compose restart prometheus >> %LOG_FILE% 2>&1
docker-compose restart grafana >> %LOG_FILE% 2>&1

echo Waiting 15 seconds for services to restart...
timeout /t 15 /nobreak > nul

echo.
echo ODAF Pipeline services:
echo ----------------------
echo Airflow:     http://localhost:8081      (user: airflow, password: airflow)
echo Spark UI:    http://localhost:8084
echo Grafana:     http://localhost:3001      (user: admin, password: admin)
echo Prometheus:  http://localhost:9091
echo Kafka UI:    http://localhost:8085
echo JupyterLab:  http://localhost:8890      (no password)
echo MinIO:       http://localhost:9001      (user: minioadmin, password: minioadmin)
echo.
echo ODAF Pipeline started successfully!
echo ODAF Pipeline started successfully! >> %LOG_FILE%

echo.
echo To see container logs, run: docker-compose logs [service_name]
echo To stop all containers, run: docker-compose down
echo.

pause
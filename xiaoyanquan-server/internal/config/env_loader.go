package config

import (
	"bufio"
	"os"
	"strings"
)

// LoadEnvFiles 按顺序加载 .env 与环境专属文件（如 .env.production）。
// 已经在系统环境中存在的变量不会被覆盖。
func LoadEnvFiles() {
	loadEnvFile(".env")

	appEnv := strings.TrimSpace(os.Getenv("APP_ENV"))
	if appEnv == "" {
		appEnv = strings.TrimSpace(os.Getenv("SERVER_MODE"))
	}
	if appEnv == "" {
		return
	}

	loadEnvFile(".env." + appEnv)
}

func loadEnvFile(path string) {
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}

		val := strings.TrimSpace(parts[1])
		if len(val) >= 2 {
			if (val[0] == '"' && val[len(val)-1] == '"') || (val[0] == '\'' && val[len(val)-1] == '\'') {
				val = val[1 : len(val)-1]
			}
		}
		_ = os.Setenv(key, val)
	}
}

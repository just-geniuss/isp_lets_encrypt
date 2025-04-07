# isp_lets_encrypt

## Для запуска:

```bash
sudo apt update -y
sudo apt upgrade -y
sudo apt install git -y
git clone https://github.com/just-geniuss/isp_lets_encrypt.git
cd isp_lets_encrypt
chmod +x isp_bulk_add.sh
sudo ./isp_bulk_add.sh
```
---

## ‼️Убедитесь в существовании domains.txt в директории со скриптом

Для копирования файла, из директории со скриптом (isp_lets_encrypt) введите команду:
```bash
cp [Путь к файлу]/domains.txt .
```

Скопировать из родительской директории:
```bash
cp ../domains.txt .
```



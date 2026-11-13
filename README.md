# MikroTik DNS Leak Kill-Switch (Blackhole Routes)

اسکریپتی برای RouterOS که به‌صورت خودکار روی **همه‌ی Routing Table های موجود** (به‌جز `main`) یک روت Blackhole برای `0.0.0.0/0` و `::/0` با Distance بالا (پیش‌فرض ۱۰) می‌سازد؛ به این ترتیب اگر تونل/گیت‌وی اصلی آن جدول قطع شود، ترافیک به‌جای لو رفتن از مسیر دیگر (و لو رفتن DNS/IP واقعی)، به‌طور کامل Drop می‌شود (Kill-Switch).

## ⚠️ نکته‌ی مهم: عدم سازگاری با RouterOS نسخه‌ی ۶ (v6)

این اسکریپت **فقط برای RouterOS v7 (نسخه‌ی ۷.۱۶.۲ به بعد)** نوشته شده و روی **RouterOS v6 اصلاً کار نمی‌کند**. دلایل:

1. **سینتکس Blackhole فرق دارد.** در v7.16.2+ باید کلمه‌ی `blackhole` را به‌تنهایی (بدون `=yes` و بدون `type=`) در دستور `add` نوشت. در v6 باید از `type=blackhole` استفاده کرد:
   ```
   /ip route add dst-address=0.0.0.0/0 type=blackhole distance=10
   ```
2. **معماری Multi-Routing-Table کاملاً متفاوت است.** v7 از منوی `/routing table` و پارامتر `routing-table=` روی روت‌ها استفاده می‌کند (چیزی که این اسکریپت با `[/routing table find]` پیمایش می‌کند). v6 چنین منویی ندارد؛ در v6 چند-مسیریابی معمولاً با `routing-mark` روی روت‌ها + قوانین `mark-routing` در `/ip firewall mangle` پیاده می‌شود، نه با جدول‌های نام‌گذاری‌شده.
3. به همین دلیل حتی اگر سینتکس `type=blackhole` را روی v6 اصلاح کنید، منطق `:foreach tId in=[/routing table find]` روی v6 اصلاً معنا و اجرای درستی ندارد.

➡️ اگر روی RouterOS v6 هستید، باید یک اسکریپت جدا بنویسید که به‌جای `/routing table find`، لیست `routing-mark` های تعریف‌شده در `/ip firewall mangle` را پیمایش کند و برای هر کدام یک روت با `type=blackhole routing-mark=<mark-name>` بسازد. این مخزن/اسکریپت برای آن حالت پوشش نمی‌دهد.

## پیش‌نیازها
- RouterOS **v7.16.2 یا بالاتر** (تست‌شده روی v7.21.5 و v7.24.6)
- دسترسی ادمین به ترمینال یا WinBox/WebFig

## نصب

### روش ۱ (پیشنهادی): WinBox/WebFig
1. **System → Scripts → Add New (+)**
2. Name: `dns-leak-killswitch`
3. Policy: `read` و `write` را تیک بزنید.
4. محتوای فایل `mikrotik-blackhole-killswitch.rsc` را داخل کادر Source پیست کنید.
5. Apply/OK.
6. **System → Scheduler → Add New**: Interval را `00:15:00` بگذارید و در Event بنویسید:
   ```
   /system script run dns-leak-killswitch
   ```

### روش ۲: از طریق ترمینال
```
/system script add name=dns-leak-killswitch policy=read,write source="
:local blackholeDistance 10;
:local excludeTables {\"main\"};
:local prefixFilter \"\";
:local tag \"killswitch\";

:foreach tId in=[/routing table find where !dynamic] do={
    :local tName [/routing table get \$tId name];
    :local skip false;
    :foreach ex in=\$excludeTables do={
        :if (\$tName = \$ex) do={ :set skip true; };
    };
    :if (\$prefixFilter != \"\" && [:find \$tName \$prefixFilter] != 0) do={ :set skip true; };
    :if (\$skip = false) do={
        :if ([:len [/ip route find where routing-table=\$tName blackhole=yes dst-address=\"0.0.0.0/0\"]] = 0) do={
            /ip route add dst-address=\"0.0.0.0/0\" blackhole distance=\$blackholeDistance routing-table=\$tName comment=\$tag;
        };
        :if ([:len [/ipv6 route find where routing-table=\$tName blackhole=yes dst-address=\"::/0\"]] = 0) do={
            /ipv6 route add dst-address=\"::/0\" blackhole distance=\$blackholeDistance routing-table=\$tName comment=\$tag;
        };
    };
};
"

/system scheduler add name=dns-leak-killswitch-scheduler interval=15m start-time=startup policy=read,write,test on-event="/system script run dns-leak-killswitch"
```

## تنظیمات قابل تغییر
در ابتدای اسکریپت:
- `blackholeDistance` (پیش‌فرض `10`): Distance روت Blackhole. باید از Distance روت واقعی تونل بیشتر باشد تا فقط زمانی فعال شود که مسیر اصلی از دسترس خارج شود.
- `excludeTables` (پیش‌فرض `{"main"}`): لیست Routing Table هایی که باید نادیده گرفته شوند.
- `tag` (پیش‌فرض `"killswitch"`): comment روت‌هایی که اسکریپت می‌سازد. حذف و بررسی با همین comment انجام می‌شود.
- `prefixFilter` (پیش‌فرض `""`): اگر مقداردهی شود (مثلاً `"to-"`)، فقط روی جدول‌هایی که اسمشان با این پیشوند شروع می‌شود اجرا می‌شود.

## نحوه‌ی کار
1. هر ۱۵ دقیقه (توسط Scheduler) اسکریپت اجرا می‌شود.
2. تمام Routing Table های موجود را با `[/routing table find where !dynamic]` می‌خواند (جدول‌های dynamic مثل `main` و جدول‌های VRF نادیده گرفته می‌شوند؛ شامل هر جدولی که بعداً برای یک تونل جدید ساخته شود — بدون نیاز به تغییر دستی اسکریپت).
3. برای هر جدول (به‌جز موارد Exclude شده)، اگر روت Blackhole برای `0.0.0.0/0` (IPv4) یا `::/0` (IPv6) وجود نداشته باشد، آن را با comment `killswitch` می‌سازد.
4. چون Distance این روت (۱۰) بالاتر از Distance روت واقعی تونل است، فقط زمانی Active می‌شود که مسیر اصلی از کار بیفتد — یعنی دقیقاً یک Kill-Switch در برابر نشت DNS/IP.

## بررسی و تست
```
/ip route print where comment="killswitch"
/ipv6 route print where comment="killswitch"
/system script run dns-leak-killswitch
/system scheduler print
```
برای تست واقعی نشت DNS، از سایت dnsleaktest.com یا ipleak.net استفاده کنید، در حالی که تونل/گیت‌وی مربوطه را عمداً Down می‌کنید.

## حذف
```
/system scheduler remove dns-leak-killswitch-scheduler
/system script remove dns-leak-killswitch
/ip route remove [find comment="killswitch"]
/ipv6 route remove [find comment="killswitch"]
```

فقط روت‌هایی که خود اسکریپت ساخته (با comment `killswitch`) حذف می‌شوند و روت‌های Blackhole دستی شما دست‌نخورده می‌مانند.

## لایسنس
MIT — استفاده، تغییر و توزیع آزاد است.

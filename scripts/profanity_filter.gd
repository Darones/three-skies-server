class_name ProfanityFilter
extends RefCounted

# Простая проверка ников на мат и грубые оскорбления.
# Список можно расширять; сервер проверяет те же корни.

const ROOTS := [
	"хуй", "хуё", "хуе", "хую", "хуя",
	"пизд",
	"ебат", "ебал", "ебан", "ебуч", "ебёт", "ебет", "ебу", "ебись", "ебля",
	"ёб", "ёба", "ёбу",
	"бля", "блят",
	"сука", "суки", "суке", "суку", "суч",
	"мудак", "мудил", "мудоз",
	"гандон",
	"залуп",
	"дроч",
	"пидор", "пидар", "педик",
	"шлюх",
	"мраз",
	"ублюд",
	"долбо",
	"дебил", "кретин",
	"нацист", "нацизм", "фашист",
	"fuck", "shit", "bitch", "cunt", "dick", "cock", "pussy",
	"asshole", "nigger", "faggot", "whore", "slut", "rapist",
	"nazi", "retard",
]


static func contains(text: String) -> bool:
	var normalized := _normalize(text)
	for root in ROOTS:
		if normalized.contains(root):
			return true
	return false


static func _normalize(text: String) -> String:
	var lower := text.to_lower()
	var result := ""
	for index in lower.length():
		var ch := lower[index]
		match ch:
			"0":
				ch = "о"
			"1":
				ch = "и"
			"3":
				ch = "е"
			"4":
				ch = "а"
			"5":
				ch = "с"
			"7":
				ch = "т"
			"@":
				ch = "а"
			"$":
				ch = "с"
		if ch.is_empty():
			continue
		var code := ch.unicode_at(0)
		var is_cyrillic := (code >= 0x430 and code <= 0x44F) or code == 0x451
		var is_latin := code >= 0x61 and code <= 0x7A
		if is_cyrillic or is_latin:
			result += ch
	return result

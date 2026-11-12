"use strict";

const STORAGE_KEY = "sky-shards.sound-picker.v1";
const AUDIO_EXTENSIONS = new Set(["ogg", "oga", "wav", "mp3", "flac", "m4a", "aac", "opus", "webm", "aiff", "aif"]);

const SLOT_GROUPS = [
	{
		id: "warrior",
		title: "Воин",
		slots: [
			["attack", "Атака"],
			["skill1", "Теневой рывок"],
			["skill2", "Жажда крови"],
			["ult", "Крик ужаса (ульта)"],
			["hit", "Получение урона"],
			["death", "Смерть"],
		],
	},
	{
		id: "fairy",
		title: "Фея",
		slots: [
			["attack", "Атака"],
			["skill1", "Оглушающий выстрел"],
			["skill2", "100% Крит"],
			["ult", "Благословение (ульта)"],
			["hit", "Получение урона"],
			["death", "Смерть"],
		],
	},
	{
		id: "mage",
		title: "Маг",
		slots: [
			["attack", "Атака"],
			["skill1", "Лозы"],
			["skill2", "Исцеление"],
			["ult", "Грозовой шквал (ульта)"],
			["hit", "Получение урона"],
			["death", "Смерть"],
		],
	},
	{
		id: "misc",
		title: "Разное",
		slots: [
			["shard_delivered", "Отнёс осколок на базу"],
			["shard_picked", "Подобрал осколок"],
			["coin_pickup", "Собрал монеты"],
			["shell_hit", "Удар по Оболочке"],
			["shell_destroyed", "Уничтожение Оболочки"],
			["victory", "Победа"],
			["defeat", "Поражение"],
			["match_start", "Старт матча"],
		],
	},
];

const TOTAL_SLOTS = SLOT_GROUPS.reduce((sum, group) => sum + group.slots.length, 0);

const els = {
	pickFolder: document.getElementById("pick-folder"),
	loadCandidates: document.getElementById("load-candidates"),
	rescan: document.getElementById("rescan"),
	fallbackInput: document.getElementById("fallback-input"),
	supportWarning: document.getElementById("support-warning"),
	search: document.getElementById("search"),
	folderName: document.getElementById("folder-name"),
	soundList: document.getElementById("sound-list"),
	soundsEmpty: document.getElementById("sounds-empty"),
	soundsCount: document.getElementById("sounds-count"),
	assignedCount: document.getElementById("assigned-count"),
	slots: document.getElementById("slots"),
	status: document.getElementById("status"),
	save: document.getElementById("save"),
	copyJson: document.getElementById("copy-json"),
	toast: document.getElementById("toast"),
};

const state = {
	sounds: [],
	selectedSoundId: null,
	assignments: createEmptyAssignments(),
	dirty: false,
	folderLabel: "",
	lastDirectoryHandle: null,
};

const player = new Audio();
player.preload = "none";

let currentObjectUrl = null;
let toastTimer = null;

function createEmptyAssignments() {
	const result = {};
	for (const group of SLOT_GROUPS) {
		result[group.id] = {};
		for (const [key] of group.slots) {
			result[group.id][key] = null;
		}
	}
	return result;
}

function normalizeAssignments(raw) {
	const result = createEmptyAssignments();
	if (!raw || typeof raw !== "object") {
		return result;
	}
	for (const group of SLOT_GROUPS) {
		const source = raw[group.id];
		if (!source || typeof source !== "object") {
			continue;
		}
		for (const [key] of group.slots) {
			const value = source[key];
			if (!value) {
				continue;
			}
			if (typeof value === "string") {
				result[group.id][key] = { name: value, path: "" };
			} else if (typeof value === "object" && typeof value.name === "string" && value.name.length > 0) {
				result[group.id][key] = {
					name: value.name,
					path: typeof value.path === "string" ? value.path : "",
				};
			}
		}
	}
	return result;
}

function el(tag, className, text) {
	const node = document.createElement(tag);
	if (className) {
		node.className = className;
	}
	if (text !== undefined) {
		node.textContent = text;
	}
	return node;
}

function isAudioFile(fileName) {
	const dot = fileName.lastIndexOf(".");
	if (dot < 0) {
		return false;
	}
	return AUDIO_EXTENSIONS.has(fileName.slice(dot + 1).toLowerCase());
}

function compareSounds(a, b) {
	return a.path.localeCompare(b.path, "ru", { numeric: true, sensitivity: "base" });
}

function findSound(record) {
	if (!record) {
		return null;
	}
	if (record.path) {
		const byPath = state.sounds.find((sound) => sound.path === record.path);
		if (byPath) {
			return byPath;
		}
	}
	return state.sounds.find((sound) => sound.name === record.name) || null;
}

function countAssigned() {
	let count = 0;
	for (const group of SLOT_GROUPS) {
		for (const [key] of group.slots) {
			if (state.assignments[group.id][key]) {
				count += 1;
			}
		}
	}
	return count;
}

function setStatus(text) {
	els.status.textContent = text;
	els.status.classList.toggle("is-dirty", state.dirty);
}

function showNotice(message) {
	els.supportWarning.textContent = message;
	els.supportWarning.classList.remove("hidden");
}

function toast(message, isError = false) {
	els.toast.textContent = message;
	els.toast.classList.toggle("is-error", isError);
	els.toast.classList.add("is-visible");
	clearTimeout(toastTimer);
	toastTimer = setTimeout(() => {
		els.toast.classList.remove("is-visible");
	}, 2800);
}

function updateCounts() {
	els.assignedCount.textContent = `${countAssigned()} / ${TOTAL_SLOTS}`;
}

function renderSounds() {
	const query = els.search.value.trim().toLowerCase();
	const filtered = state.sounds.filter((sound) => {
		if (!query) {
			return true;
		}
		return sound.name.toLowerCase().includes(query) || sound.path.toLowerCase().includes(query);
	});

	els.soundsCount.textContent = String(state.sounds.length);
	els.soundList.replaceChildren();

	if (filtered.length === 0) {
		els.soundsEmpty.classList.remove("hidden");
		if (state.folderLabel === "") {
			els.soundsEmpty.textContent = "Выберите папку со звуками — файлы появятся здесь.";
		} else if (state.sounds.length === 0) {
			els.soundsEmpty.textContent = "В выбранной папке не найдено аудиофайлов (.ogg, .wav, .mp3 и т.д.).";
		} else {
			els.soundsEmpty.textContent = "Ничего не найдено по запросу.";
		}
		return;
	}

	els.soundsEmpty.classList.add("hidden");
	const fragment = document.createDocumentFragment();

	for (const sound of filtered) {
		const item = el("li", "sound-item");
		item.dataset.id = sound.id;
		const isSelected = sound.id === state.selectedSoundId;
		if (isSelected) {
			item.classList.add("is-selected");
		}

		const main = el("div", "sound-main");
		main.appendChild(el("span", "sound-name", sound.name));
		if (sound.path !== sound.name) {
			main.appendChild(el("span", "sound-path", sound.path));
		}
		item.appendChild(main);

		const actions = el("div", "sound-actions");
		const playButton = el("button", "icon-btn", "▶");
		playButton.type = "button";
		playButton.title = "Прослушать";
		playButton.dataset.soundAction = "play";
		actions.appendChild(playButton);

		const assignButton = el("button", isSelected ? "btn btn-small is-selected" : "btn btn-small", isSelected ? "Выбран" : "Назначить");
		assignButton.type = "button";
		assignButton.dataset.soundAction = "assign";
		assignButton.title = isSelected ? "Снять выбор" : "Выбрать звук, затем кликнуть по слоту";
		actions.appendChild(assignButton);

		item.appendChild(actions);
		fragment.appendChild(item);
	}

	els.soundList.appendChild(fragment);
}

function renderSlots() {
	els.slots.replaceChildren();
	let assignedTotal = 0;

	for (const group of SLOT_GROUPS) {
		let assignedInGroup = 0;
		const section = el("section", "slot-group");
		const heading = el("h3");
		heading.appendChild(document.createTextNode(group.title));
		const groupCount = el("span", "group-count");
		heading.appendChild(groupCount);
		section.appendChild(heading);

		const list = el("div", "slot-list");
		for (const [key, label] of group.slots) {
			const record = state.assignments[group.id][key];
			const sound = findSound(record);
			const isFilled = Boolean(record);
			const isMissing = isFilled && state.folderLabel !== "" && !sound;
			if (isFilled) {
				assignedInGroup += 1;
				assignedTotal += 1;
			}

			const slot = el("div", "slot");
			slot.dataset.group = group.id;
			slot.dataset.key = key;
			if (isFilled) {
				slot.classList.add("is-filled");
			} else {
				slot.classList.add("is-empty");
			}
			if (isMissing) {
				slot.classList.add("is-missing");
			}

			const main = el("button", "slot-main");
			main.type = "button";
			main.dataset.action = "slot-main";
			main.appendChild(el("span", "slot-label", label));
			main.appendChild(el("span", "slot-file", record ? record.name : "Не назначен"));
			if (isMissing) {
				main.title = "Файл не найден в выбранной папке";
			} else if (isFilled) {
				main.title = "Кликните, чтобы назначить выбранный звук";
			} else {
				main.title = "Назначить выбранный звук в этот слот";
			}
			slot.appendChild(main);

			const actions = el("div", "slot-actions");
			const playButton = el("button", "icon-btn", "▶");
			playButton.type = "button";
			playButton.dataset.action = "play-slot";
			playButton.title = isFilled ? "Прослушать назначенный звук" : "Слот пуст";
			playButton.disabled = !isFilled || isMissing;
			actions.appendChild(playButton);

			const clearButton = el("button", "clear-btn", "Очистить");
			clearButton.type = "button";
			clearButton.dataset.action = "clear-slot";
			clearButton.title = isFilled ? "Очистить слот" : "Слот уже пуст";
			clearButton.disabled = !isFilled;
			actions.appendChild(clearButton);

			slot.appendChild(actions);
			list.appendChild(slot);
		}

		groupCount.textContent = `${assignedInGroup} / ${group.slots.length}`;
		section.appendChild(list);
		els.slots.appendChild(section);
	}

	updateCounts();
	if (assignedTotal === 0) {
		els.assignedCount.textContent = `0 / ${TOTAL_SLOTS}`;
	}
}

function selectSound(soundId) {
	const sound = state.sounds.find((item) => item.id === soundId);
	if (!sound) {
		return;
	}
	state.selectedSoundId = state.selectedSoundId === soundId ? null : soundId;
	renderSounds();
	if (state.selectedSoundId) {
		setStatus(`Выбран звук: «${sound.name}». Кликните по слоту справа.`);
	} else {
		setStatus("Выбор снят.");
	}
}

function assignSelected(groupId, key) {
	const sound = state.sounds.find((item) => item.id === state.selectedSoundId);
	if (!sound) {
		toast("Сначала нажмите «Назначить» у звука слева.", true);
		return;
	}
	state.assignments[groupId][key] = { name: sound.name, path: sound.path };
	state.dirty = true;
	renderSlots();
	const group = SLOT_GROUPS.find((item) => item.id === groupId);
	const slotLabel = group ? group.slots.find(([slotKey]) => slotKey === key)?.[1] : key;
	setStatus(`Назначено: «${sound.name}» → ${group ? group.title : groupId} · ${slotLabel}. Не забудьте сохранить.`);
	toast(`«${sound.name}» → ${slotLabel}`);
}

function clearSlot(groupId, key) {
	if (!state.assignments[groupId][key]) {
		return;
	}
	state.assignments[groupId][key] = null;
	state.dirty = true;
	renderSlots();
	setStatus("Слот очищен. Не забудьте сохранить.");
}

function stopPlayback() {
	player.pause();
	player.removeAttribute("src");
	player.load();
	if (currentObjectUrl) {
		URL.revokeObjectURL(currentObjectUrl);
		currentObjectUrl = null;
	}
}

async function playSound(sound) {
	try {
		if (sound.url) {
			stopPlayback();
			player.src = sound.url;
			player.currentTime = 0;
			await player.play();
			setStatus(`▶ ${sound.name}`);
			player.onended = () => {
				stopPlayback();
				setStatus("Готово.");
			};
			return;
		}
		const file = sound.file || (sound.handle ? await sound.handle.getFile() : null);
		if (!file) {
			throw new Error("файл недоступен, выберите папку заново");
		}
		stopPlayback();
		currentObjectUrl = URL.createObjectURL(file);
		player.src = currentObjectUrl;
		player.currentTime = 0;
		await player.play();
		setStatus(`▶ ${sound.name}`);
		player.onended = () => {
			stopPlayback();
			setStatus("Готово.");
		};
	} catch (error) {
		toast(`Не удалось воспроизвести «${sound.name}»: ${error.message}`, true);
	}
}

function playRecord(record) {
	const sound = findSound(record);
	if (sound) {
		void playSound(sound);
		return;
	}
	if (state.folderLabel === "") {
		toast("Сначала выберите папку со звуками.", true);
	} else {
		toast(`Файл «${record.name}» не найден в выбранной папке.`, true);
	}
}

function buildJson() {
	const result = {};
	for (const group of SLOT_GROUPS) {
		result[group.id] = {};
		for (const [key] of group.slots) {
			const record = state.assignments[group.id][key];
			result[group.id][key] = record ? record.name : null;
		}
	}
	return result;
}

async function copyJson() {
	const text = JSON.stringify(buildJson(), null, 2);
	try {
		if (navigator.clipboard && window.isSecureContext) {
			await navigator.clipboard.writeText(text);
			toast("JSON скопирован в буфер обмена.");
			return;
		}
		if (fallbackCopy(text)) {
			toast("JSON скопирован в буфер обмена.");
		} else {
			toast("Не удалось скопировать JSON. Проверьте разрешения браузера.", true);
		}
	} catch (error) {
		toast(`Не удалось скопировать JSON: ${error.message}`, true);
	}
}

function fallbackCopy(text) {
	const area = document.createElement("textarea");
	area.value = text;
	area.setAttribute("readonly", "");
	area.style.position = "fixed";
	area.style.top = "-1000px";
	area.style.opacity = "0";
	document.body.appendChild(area);
	area.select();
	let copied = false;
	try {
		copied = document.execCommand("copy");
	} catch (error) {
		copied = false;
	}
	area.remove();
	return copied;
}

function saveAssignments() {
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify({ version: 1, assignments: state.assignments }));
		state.dirty = false;
		setStatus(`Сохранено: ${countAssigned()} из ${TOTAL_SLOTS} слотов.`);
		toast("Назначения сохранены в браузере.");
	} catch (error) {
		toast(`Не удалось сохранить: ${error.message}`, true);
	}
}

function loadSaved() {
	let raw = null;
	try {
		raw = localStorage.getItem(STORAGE_KEY);
	} catch (error) {
		return;
	}
	if (!raw) {
		return;
	}
	try {
		const data = JSON.parse(raw);
		const source = data && data.assignments ? data.assignments : data;
		state.assignments = normalizeAssignments(source);
		setStatus("Загружены сохранённые назначения. Выберите папку, чтобы прослушать звуки.");
	} catch (error) {
		console.warn("Не удалось прочитать сохранённые назначения:", error);
	}
}

function supportsDirectoryInput() {
	const input = document.createElement("input");
	return "webkitdirectory" in input;
}

function checkSupport() {
	if (typeof window.showDirectoryPicker === "function") {
		return;
	}
	if (supportsDirectoryInput()) {
		showNotice("File System Access API недоступен, используется запасной выбор папки. После перезагрузки страницы папку нужно выбрать снова.");
	} else {
		showNotice("Этот браузер не умеет открывать папки. Откройте страницу в Chrome, Edge или другом Chromium-браузере.");
	}
}

async function walkDirectory(handle, prefix, out, depth) {
	if (depth > 24) {
		return;
	}
	for await (const entry of handle.values()) {
		if (entry.name.startsWith(".")) {
			continue;
		}
		const path = prefix ? `${prefix}/${entry.name}` : entry.name;
		if (entry.kind === "file") {
			if (isAudioFile(entry.name)) {
				out.push({ id: path, name: entry.name, path, handle: entry, file: null });
			}
		} else if (entry.kind === "directory") {
			await walkDirectory(entry, path, out, depth + 1);
		}
	}
}

function applySounds(found, folderLabel) {
	state.sounds = found.sort(compareSounds);
	state.folderLabel = folderLabel;
	state.selectedSoundId = null;
	els.search.disabled = false;
	els.rescan.disabled = false;
	els.folderName.textContent = `Папка: ${folderLabel} · файлов: ${found.length}`;
	els.folderName.title = folderLabel;
	renderSounds();
	renderSlots();
	setStatus(`Загружено звуков: ${found.length}. Нажмите «Назначить» у звука.`);
}

async function loadDirectory(handle) {
	setStatus("Читаю папку…");
	const found = [];
	await walkDirectory(handle, "", found, 0);
	state.lastDirectoryHandle = handle;
	applySounds(found, handle.name);
	toast(`Загружено звуков: ${found.length}.`);
}

async function chooseFolder() {
	if (typeof window.showDirectoryPicker === "function") {
		try {
			const handle = await window.showDirectoryPicker({ mode: "read" });
			await loadDirectory(handle);
		} catch (error) {
			if (error.name !== "AbortError") {
				showNotice(`Не удалось открыть папку: ${error.message}`);
			}
		}
		return;
	}
	if (supportsDirectoryInput()) {
		els.fallbackInput.value = "";
		els.fallbackInput.click();
		return;
	}
	showNotice("Этот браузер не умеет открывать папки. Откройте страницу в Chrome или Edge.");
}

async function rescanFolder() {
	if (state.lastDirectoryHandle) {
		try {
			const handle = state.lastDirectoryHandle;
			if (typeof handle.queryPermission === "function") {
				let permission = await handle.queryPermission({ mode: "read" });
				if (permission !== "granted" && typeof handle.requestPermission === "function") {
					permission = await handle.requestPermission({ mode: "read" });
				}
				if (permission !== "granted") {
					toast("Нет доступа к папке. Выберите её заново.", true);
					return;
				}
			}
			await loadDirectory(handle);
		} catch (error) {
			toast(`Не удалось перечитать папку: ${error.message}`, true);
		}
		return;
	}
	if (supportsDirectoryInput()) {
		els.fallbackInput.value = "";
		els.fallbackInput.click();
		return;
	}
	await chooseFolder();
}

function loadFromFileInput(fileList) {
	const files = Array.from(fileList || []);
	const audioFiles = files.filter((file) => isAudioFile(file.name));
	const firstPath = files[0]?.webkitRelativePath || "";
	const rootName = firstPath.includes("/") ? firstPath.split("/")[0] : "выбранная папка";
	const found = audioFiles.map((file) => {
		const relative = file.webkitRelativePath || file.name;
		const parts = relative.split("/");
		const path = parts.length > 1 ? parts.slice(1).join("/") : file.name;
		return { id: path, name: file.name, path, handle: null, file };
	});
	state.lastDirectoryHandle = null;
	applySounds(found, rootName);
	toast(`Загружено звуков: ${found.length}.`);
}

async function loadCandidates() {
	setStatus("Загружаю кандидатов…");
	try {
		const response = await fetch("candidates/manifest.json", { cache: "no-store" });
		if (!response.ok) {
			throw new Error(`HTTP ${response.status}`);
		}
		const data = await response.json();
		const found = (data.files || []).map((file) => ({
			id: file.path,
			name: file.name,
			path: file.path,
			url: file.path,
			handle: null,
			file: null,
		}));
		state.sounds = found.sort(compareSounds);
		state.folderLabel = "кандидаты";
		state.selectedSoundId = null;
		const loaded = normalizeAssignments(data.assignments || {});
		const oldDefaultNames = new Set([
			"misc_victory_epic.wav",
			"misc_victory_fanfare.wav",
			"misc_defeat_dark.wav",
			"misc_match_start.wav",
			"misc_coin_pickup.wav",
			"mage_root_vines.wav",
			"warrior_death_scream.wav",
			"fairy_death_scream.wav",
			"mage_death_scream.wav",
			"death_soft_aaa.wav",
			"mage_attack_fire.wav",
			"mage_attack_arcane.wav",
			"warrior_fear_roar.wav",
			"mage_lightning.wav",
		]);
		let merged = false;
		for (const group of SLOT_GROUPS) {
			for (const [key] of group.slots) {
				const current = state.assignments[group.id][key];
				const shouldReplace = !current || oldDefaultNames.has(current.name);
				if (shouldReplace && loaded[group.id][key]) {
					state.assignments[group.id][key] = loaded[group.id][key];
					merged = true;
				}
			}
		}
		state.dirty = merged;
		els.search.disabled = false;
		els.rescan.disabled = true;
		els.folderName.textContent = `Папка: кандидаты · файлов: ${found.length}`;
		renderSounds();
		renderSlots();
		setStatus(`Загружено кандидатов: ${found.length}. Жмите ▶ у слота или у файла.`);
		toast(`Кандидаты загружены: ${found.length}.`);
	} catch (error) {
		showNotice("Не удалось загрузить candidates/manifest.json. Откройте страницу через локальный HTTP-сервер (например, python -m http.server) и обновите её.");
		setStatus("Кандидаты не загрузились.");
		toast(`Ошибка: ${error.message}`, true);
	}
}


function init() {
	loadSaved();
	checkSupport();
	renderSounds();
	renderSlots();
	updateCounts();

	els.pickFolder.addEventListener("click", () => {
		void chooseFolder();
	});
	els.loadCandidates.addEventListener("click", () => {
		void loadCandidates();
	});
	els.rescan.addEventListener("click", () => {
		void rescanFolder();
	});
	els.fallbackInput.addEventListener("change", () => {
		loadFromFileInput(els.fallbackInput.files);
	});
	els.soundList.addEventListener("click", (event) => {
		const item = event.target.closest(".sound-item");
		const actionElement = event.target.closest("[data-sound-action]");
		if (!item || !actionElement) {
			return;
		}
		const sound = state.sounds.find((entry) => entry.id === item.dataset.id);
		if (!sound) {
			return;
		}
		if (actionElement.dataset.soundAction === "play") {
			void playSound(sound);
		} else if (actionElement.dataset.soundAction === "assign") {
			selectSound(sound.id);
		}
	});
	els.slots.addEventListener("click", (event) => {
		const slot = event.target.closest(".slot");
		if (!slot) {
			return;
		}
		const groupId = slot.dataset.group;
		const key = slot.dataset.key;
		const actionElement = event.target.closest("[data-action]");
		const record = state.assignments[groupId][key];
		if (!actionElement) {
			return;
		}
		const action = actionElement.dataset.action;
		if (action === "play-slot") {
			if (record) {
				playRecord(record);
			}
		} else if (action === "clear-slot") {
			clearSlot(groupId, key);
		} else if (action === "slot-main") {
			if (state.selectedSoundId) {
				assignSelected(groupId, key);
			} else if (record) {
				playRecord(record);
			} else {
				toast("Сначала нажмите «Назначить» у звука слева.", true);
			}
		}
	});
	els.search.addEventListener("input", renderSounds);
	els.save.addEventListener("click", saveAssignments);
	els.copyJson.addEventListener("click", () => {
		void copyJson();
	});
	window.addEventListener("keydown", (event) => {
		if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
			event.preventDefault();
			saveAssignments();
		}
	});
	window.addEventListener("beforeunload", (event) => {
		if (!state.dirty) {
			return;
		}
		event.preventDefault();
		event.returnValue = "";
	});
}

init();

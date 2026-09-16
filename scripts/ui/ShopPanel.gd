extends CanvasLayer
## 小兰的商店面板。普通强化和唱片领取使用同一套界面资源，模式由 open() 切换。

signal closed

const MODE_UPGRADES := "upgrades"
const MODE_RECORDS := "records"

@onready var title_label: Label = $Overlay/Center/Panel/Margin/VBox/Title
@onready var currency_label: Label = $Overlay/Center/Panel/Margin/VBox/Currency
@onready var spent_label: Label = $Overlay/Center/Panel/Margin/VBox/Spent
@onready var upgrades_page: Control = $Overlay/Center/Panel/Margin/VBox/UpgradesPage
@onready var records_page: Control = $Overlay/Center/Panel/Margin/VBox/RecordsPage
@onready var hp_price_label: Label = $Overlay/Center/Panel/Margin/VBox/UpgradesPage/HpPrice
@onready var hp_status_label: Label = $Overlay/Center/Panel/Margin/VBox/UpgradesPage/HpStatus
@onready var hp_buy_button: Button = $Overlay/Center/Panel/Margin/VBox/UpgradesPage/HpBuyButton
@onready var attack_buy_button: Button = $Overlay/Center/Panel/Margin/VBox/UpgradesPage/AttackBuyButton
@onready var record_status_label: Label = $Overlay/Center/Panel/Margin/VBox/RecordsPage/RecordStatus
@onready var record_claim_button: Button = $Overlay/Center/Panel/Margin/VBox/RecordsPage/RecordClaimButton
@onready var close_button: Button = $Overlay/Center/Panel/Margin/VBox/CloseButton

var _mode := MODE_UPGRADES


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hp_buy_button.pressed.connect(_on_hp_buy_pressed)
	attack_buy_button.pressed.connect(_on_attack_buy_pressed)
	record_claim_button.pressed.connect(_on_record_claim_pressed)
	close_button.pressed.connect(close)
	hide()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open(mode: String) -> void:
	_mode = MODE_RECORDS if mode == MODE_RECORDS else MODE_UPGRADES
	_refresh()
	show()
	get_tree().paused = true
	if _mode == MODE_RECORDS:
		record_claim_button.grab_focus()
	else:
		hp_buy_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = false
	closed.emit()


func _refresh() -> void:
	currency_label.text = "绕梁余音：%d" % GameState.notes
	spent_label.text = "累计交换：%d / 100" % GameState.total_notes_spent
	upgrades_page.visible = _mode == MODE_UPGRADES
	records_page.visible = _mode == MODE_RECORDS
	if _mode == MODE_RECORDS:
		title_label.text = "唱片"
		var record := GameState.get_record(GameState.RECORD_BRAHMS_ID)
		$Overlay/Center/Panel/Margin/VBox/RecordsPage/RecordName.text = str(record.get("title", "Brahms 唱片"))
		var owned := GameState.has_record(GameState.RECORD_BRAHMS_ID)
		record_status_label.text = "已拥有" if owned else "免费领取"
		record_claim_button.text = "已领取" if owned else "领取"
		record_claim_button.disabled = owned
	else:
		title_label.text = "交换旋律"
		var price := GameState.get_next_hp_upgrade_price()
		hp_status_label.text = "已交换 %d / %d" % [GameState.hp_upgrade_count, GameState.MAX_HP_UPGRADE_PRICES.size()]
		hp_price_label.text = "当前价格：%s 绕梁余音" % ("已全部交换" if price < 0 else str(price))
		hp_buy_button.text = "交换" if price >= 0 else "已全部交换"
		hp_buy_button.disabled = price < 0 or GameState.notes < price
		attack_buy_button.text = "暂不可购买"
		attack_buy_button.disabled = true


func _on_hp_buy_pressed() -> void:
	if not GameState.buy_hp_upgrade():
		_refresh()
		return
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("restore_full_hp"):
		player.restore_full_hp()
	GameState.save_game()
	_refresh()


func _on_attack_buy_pressed() -> void:
	pass


func _on_record_claim_pressed() -> void:
	if GameState.grant_record(GameState.RECORD_BRAHMS_ID):
		GameState.save_game()
	_refresh()

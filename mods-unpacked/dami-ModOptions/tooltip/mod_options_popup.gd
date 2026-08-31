extends InfoPopup

func get_pos_from(new_element:Node)->Vector2:
	var element_pos:Vector2 = new_element.rect_global_position
	var pos: = element_pos

	if element_pos.x > Utils.project_width / 2:
		pos.x = pos.x - _panel.rect_size.x
	else :
		pos.x = pos.x + new_element.rect_size.x / 2

	if element_pos.y > Utils.project_height / 2:
		pos.y = pos.y - _panel.rect_size.y - DIST
	else :
		pos.y = pos.y + new_element.rect_size.y

	return pos

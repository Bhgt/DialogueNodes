tool
extends Control

# Nodes
var StartNode = preload("res://addons/dialogue_nodes/nodes/StartNode.tscn")
var DialogueNode = preload("res://addons/dialogue_nodes/nodes/DialogueNode.tscn")
var EndNode = preload("res://addons/dialogue_nodes/nodes/EndNode.tscn")
var CommentNode = preload("res://addons/dialogue_nodes/nodes/CommentNode.tscn")

var startNodes # Stores all the start nodes' names
var selected  # The selected node.
var commentNodes # The names of all comment nodes
var commentsLoaded # True when done loading comments from file
var currentNode # The demo node to display
var demoDict # The dictionary of dialogue tree for demo
var demoIndex # The dict index of current dialogue

var lastSpeaker = '' # The last speaker from the last dialogue node changed
var lastPosition = Vector2.ZERO # The position of the last moved node
var lastOffset = 0 # Offset index
var lastPath = ''
var lastFile = ''

onready var fileMenu = $Main/ToolBar/FileMenu
onready var addMenu = $Main/ToolBar/AddMenu
onready var runMenu = $Main/ToolBar/RunMenu
onready var graph = $Main/Workspace/Graph
onready var sidePanel = $Main/Workspace/SidePanel
onready var sidePanelToggle = $Main/Statusbar/PanelToggle
onready var fileName = $Main/Statusbar/FileName
onready var demo = $Demo
onready var tween = $Demo/Tween


func _ready():
	selected = null
	commentNodes = []
	startNodes = []
	
	fileMenu.get_popup().connect("id_pressed", self, '_on_file_menu_pressed')
	addMenu.get_popup().connect("id_pressed", self, '_on_add_menu_pressed')
	runMenu.get_popup().connect("id_pressed", self, '_on_run_menu_pressed')


func addNode(node, nodeId= ''):
	var nodeInstance = node.instance()
	
	nodeInstance.connect('close_request', self, '_on_node_close_request', [nodeInstance])
	nodeInstance.connect('dragged', self, '_on_node_dragged')
	nodeInstance.connect('nodeModified', self, '_on_node_modified')
	
	# Default naming
	if nodeId == '':
		nodeInstance.name = '1'
		graph.add_child(nodeInstance, true)
		nodeInstance.title = nodeInstance.getType() + ' - ' + nodeInstance.name
	else:
		nodeInstance.name = nodeId
		graph.add_child(nodeInstance, false)
		nodeInstance.title += ' - ' + nodeInstance.name
	
	nodeInstance.offset = lastPosition + Vector2(20, 20) * lastOffset
	
	lastOffset += 1
	
	if node == StartNode:
		startNodes.append(nodeInstance.name)
#		if start == null:
#			start = nodeInstance
#			addMenu.get_popup().set_item_disabled(0, true)
#			$Main/Workspace/SidePanel/AddShortcuts/StartShortcut.disabled = true
	elif node == DialogueNode:
		nodeInstance.connect('speakerChanged', self, '_on_speaker_changed')
		nodeInstance.connect('slotRemoved', self, '_on_slot_removed', [nodeInstance.name])
		nodeInstance.setSpeaker(lastSpeaker)
	elif node == CommentNode:
		commentNodes.append(nodeInstance.name)
	
	return nodeInstance


func duplicateNode(node):
	
	var nodeInstance = null
	
	match node.getType():
		'Start':
			nodeInstance = addNode(StartNode)
			nodeInstance.get_node('ID').text = nodeInstance.name
			startNodes.append(nodeInstance.name)
		'Dialogue':
			nodeInstance = addNode(DialogueNode)
			
			nodeInstance.setSpeaker(node.getSpeaker())
			nodeInstance.setDialogue(node.getDialogue())
			
			nodeInstance.options.visible = node.options.visible
			nodeInstance.optionsToggle.pressed = node.optionsToggle.pressed
			
			for optionName in node.getOptionNames():
				nodeInstance.addOption(optionName)
			
		'End':
			nodeInstance = addNode(EndNode)
		'Comment':
			nodeInstance = addNode(CommentNode)
			
			nodeInstance.setCommentText(node.getCommentText())
			
			commentNodes.append(nodeInstance.name)
	
	if nodeInstance == null:
		return
	
	nodeInstance.offset = node.offset + Vector2(20, 20)
	nodeInstance.title = node.getType() + ' - ' + nodeInstance.name
	
	removeAllConnections(nodeInstance.name, nodeInstance.name)
	
	node.selected = false
	nodeInstance.selected = true
	selected = nodeInstance
	


func removeNode(node):
	# Clear hanging connections
	removeAllConnections(node.name, node.name)

	# Enable menu options if disabled
#	if node == start:
#		start = null
#		addMenu.get_popup().set_item_disabled(0, false)
#		$Main/Workspace/SidePanel/AddShortcuts/StartShortcut.disabled = false
	# Remove from startNodes if present
	if startNodes.has(node.name):
			startNodes.erase(node.name)
	# Remove from commentNodes if present
	elif commentNodes.has(node.name):
		commentNodes.erase(node.name)
	
	if node == selected:
		selected = null
	
	node.queue_free()


func removeInvalidConnections(from, from_slot= -1, to= null, to_slot= -1):
	for connection in graph.get_connection_list():
		if connection['from'] == from:
			if connection['to'] != to and connection['from_port'] == from_slot:
				graph.disconnect_node(
					connection['from'], connection['from_port'], connection['to'], connection['to_port']
				)


func removeAllConnections(from, to):
	for connection in graph.get_connection_list():
		if connection['from'] == from or connection['to'] == to:
			graph.disconnect_node(
				connection['from'], connection['from_port'], connection['to'], connection['to_port']
			)


func clearGraph():
	for child in graph.get_children():
		if child is GraphNode:
			removeNode(child)
#	start = null
	selected = null
	commentNodes.clear()


func getNextNode(nodeName):
	var connections = []
	var nextNodeNames = []
	for connection in graph.get_connection_list():
		if connection['from'] == nodeName:
			connections.append(connection)
	connections.sort_custom(self, 'sortBySlot')
	
	for connection in connections:
		nextNodeNames.append(connection['to'])
	
	return nextNodeNames

func sortBySlot(a, b):
	return a['from_port'] < b['from_port']


func isTreeComplete():
	for start in startNodes:
		if getNextNode(start).size() == 0:
			return false
	return startNodes.size() > 0


func startDemo(selectedNode):
	if isTreeComplete() and selected.getType() == 'Start':
		demoDict = toDict()
		if demoDict != null:
			demoIndex = demoDict[selectedNode.name]['Link']
			updateDemo()
	demo.popup_centered()


func updateDemo():
	if (demoDict.has(demoIndex) and demoDict[demoIndex].has('Link')):
		if demoDict[demoIndex]['Link'] == 'End':
			# End
			stopDemo()
	elif not demoDict.has(demoIndex):
		stopDemo()
	else:
		# Dialogue
		var currentDialogue = demoDict[demoIndex]
		var options = demo.get_node("Options")
		
		demo.get_node("Speaker").text = currentDialogue['Speaker']
		demo.get_node("Dialogue").bbcode_text = currentDialogue['Dialogue']
		
		#Reset options
		for i in range(1, options.get_child_count()):
			var option = options.get_child(i)
			option.text = ''
			option.disabled = true
			option.hide()
		
		for i in range(currentDialogue['Options'].size()):
			var option = options.get_child(i)
			var demoOption = currentDialogue["Options"][str(i)]
			
			option.text = demoOption['Text']
			option.disabled = false
			option.show()
			
			# Disconnect previous connections
			if options.get_child(i).is_connected('pressed', self, '_on_option_pressed'):
				options.get_child(i).disconnect('pressed', self, '_on_option_pressed')
			# Add updated connection
			options.get_child(i).connect('pressed', self, '_on_option_pressed', [demoOption['Link']])
		
		tween.interpolate_property(demo.get_node("Dialogue"), 'percent_visible', 0, 1, demo.get_node("Dialogue").text.length()*0.05, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
		tween.start()


func stopDemo():
	# Reset to default values
	demo.get_node("Speaker").text = 'Speaker'
	demo.get_node("Dialogue").bbcode_text = 'This is a test dialogue. Make a [u]node tree[/u] to test it out!'
	
	for option in demo.get_node("Options").get_children():
		option.text = 'Next'
	
	demoDict.clear()
	demo.hide()


func toDict(nodeName= '', dict= {}):
	# Initial step
	if nodeName == '':
		dict['Start'] = {}
	
		for start in startNodes:
			selected = graph.get_node(start)
			var newDict = toDict(start, dict)
			if newDict != null:
				dict['Start'][selected.getID()] = start
				dict = newDict
		
		return dict
	# If tree is complete, i.e. start -> node/s -> end
	elif isTreeComplete():
		currentNode = graph.get_node(nodeName)
		
		# Save comments
		if not dict.has('Comments'):
			var comments = {}
			
			for commentName in commentNodes:
				var commentNode = graph.get_node(commentName)
				var comment = {}
				comment['Offset'] = {'X': commentNode.offset.x, 'Y': commentNode.offset.y}
				comment['Text'] = commentNode.getCommentText()
				comments[commentName] = comment
			
			dict['Comments'] = comments
		
		# Save node tree
		match currentNode.getType():
			'Start':
				# First after start
				var firstNode = getNextNode(nodeName)[0]
				var startNode = {}
				
				startNode['StartID'] = currentNode.getID()
				startNode['Link'] = firstNode
				startNode['Offset'] = {'X': currentNode.offset.x, 'Y': currentNode.offset.y}
				
				dict[nodeName] = startNode
				return toDict(firstNode, dict)
				
			'Dialogue':
				var dialogue = {}
				var options = {}
				var optionNames = currentNode.getOptionNames()
				var optionLinks = getNextNode(currentNode.name)
				
				if optionLinks.size() == 0:
					print('Tree contains loose ends. Aborting node: ' + nodeName)
					dict[nodeName] = 'End'
					return null
				else:
					options['0'] = {
						'Text': 'Next',
						'Link': optionLinks[0]
						}
				
				for i in range(optionNames.size()):
					var option = {}
					
					option['Text'] = optionNames[i]
					option['Link'] = optionLinks[min(i, optionLinks.size()-1)]
					
					options[str(i)] = option
				
				dialogue['Speaker'] = currentNode.getSpeaker()
				dialogue['Dialogue'] = currentNode.getDialogue()
				dialogue['Options'] = options
				dialogue['Offset'] = {'X': currentNode.offset.x, 'Y': currentNode.offset.y}
				dict[nodeName] = dialogue
				
				for next in optionLinks:
					if not dict.has(next):
						var newDict = toDict(next, dict)
						if newDict != null:
							dict = newDict
				
				return dict
				
			'End':
				var endNode = {}
				
				endNode['Link'] = 'End'
				endNode['Offset'] = {'X': currentNode.offset.x, 'Y': currentNode.offset.y}
				
				dict[nodeName] = endNode
				
				return dict
				
			_:
				print('Unknown type. Ending traversal of this branch')
				
				return dict
	else:
		return null


func saveTree(path= lastPath, editing= false):
	if not isTreeComplete():
		if editing:
			$SaveAlertDialog.popup_centered()
		return
	elif path == '':
		if lastPath != '':
			path = lastPath
		elif editing:
			$SaveDialog.popup_centered()
			return
		else:
			return
	
	var dict = toDict()
	var file = File.new()
	file.open(path, File.WRITE)
	file.store_line(to_json(dict))
	file.close()
	fileName.text = lastFile


func loadTree(nodeIndex, from= null, from_slot= -1):
	# Comments
	if demoDict.has('Comments') and not commentsLoaded:
		var comments = demoDict['Comments']
		var instance
		
		for i in comments:
			instance = addNode(CommentNode, i)
			instance.offset = Vector2(comments[i]['Offset']['X'], comments[i]['Offset']['Y'])
			instance.setCommentText(comments[i]['Text'])
		
		commentsLoaded = true
	
	if nodeIndex == 'Start':
		# Load each tree in 'Start'
		for key in demoDict['Start']:
			loadTree(demoDict['Start'][key])
	elif demoDict.has(nodeIndex):
		var instance
		var node = demoDict[nodeIndex]
		var offset = Vector2(node['Offset']['X'], node['Offset']['Y'])
		
		if node.has('StartID'):
			# Start
			instance = addNode(StartNode, nodeIndex)
			instance.setID(node['StartID'])
			
			loadTree(node['Link'], nodeIndex, 0)
		elif node.has('Link') and node['Link'] == 'End':
			# End
			instance = addNode(EndNode, nodeIndex)
			
			# Connection
			if from != null and int(from_slot) > -1:
				graph.connect_node(from, int(from_slot), nodeIndex, 0)
			
		else:
			# Dialogue
			instance = addNode(DialogueNode, nodeIndex)
			
			instance.setSpeaker(node['Speaker'])
			instance.setDialogue(node['Dialogue'])
			instance.options.visible = true
			instance.optionsToggle.pressed = true
			for opId in node['Options']:
				var option = node['Options'][opId]
				instance.addOption(option['Text'])
				if not graph.has_node(option['Link']):
					loadTree(option['Link'], nodeIndex, opId)
				else:
					graph.connect_node(nodeIndex, int(opId), option['Link'], 0)
			
			# Connection
			if from != null and int(from_slot) > -1:
				graph.connect_node(from, int(from_slot), nodeIndex, 0)
		instance.offset = offset
	
	lastOffset = 1


func _on_file_menu_pressed(id):
	match id:
		0:
			clearGraph()
			fileName.text = ''
			lastPath = ''
			lastFile = ''
		1:
			$SaveDialog.popup_centered()
		2:
			$LoadTreeDialog.popup_centered()
		3:
			clearGraph()
			fileName.text = ''
			lastPath = ''
			lastFile = ''


func _on_add_menu_pressed(id):
	match id:
		0:
			addNode(StartNode)
		1:
			addNode(DialogueNode)
		2:
			addNode(EndNode)
		3:
			addNode(CommentNode)
	_on_node_modified()


func _on_StartShortcut_pressed():
	addNode(StartNode)


func _on_DialogueShortcut_pressed():
	addNode(DialogueNode)


func _on_EndShortcut_pressed():
	addNode(EndNode)


func _on_CommentShortcut_pressed():
	addNode(CommentNode)


func _on_run_menu_pressed(id):
	match id:
		0:
			startDemo(selected)
		1:
			$LoadDemoDialog.popup_centered()


func _on_node_close_request(node):
	removeNode(node)


func _on_node_dragged(from, to):
	lastPosition = to
	lastOffset = 1


func _on_node_connection_request(from, from_slot, to, to_slot):
	if from != to:
		# Remove previous connections
		removeInvalidConnections(from, from_slot)
		# Make new connection
		graph.connect_node(from, from_slot, to, to_slot)
		
		_on_node_modified()


func _on_node_disconnection_request(from, from_slot, to, to_slot):
	graph.disconnect_node(from, from_slot, to, to_slot)
	
	_on_node_modified()


func _on_delete_nodes_request():
	if selected != null:
		removeNode(selected)
		selected = null


func _on_duplicate_nodes_request():
	if selected != null:
		duplicateNode(selected)


func _on_node_selected(node):
	selected = node
	lastPosition = node.offset
	lastOffset = 0


func _on_node_modified():
	if lastFile != '':
		fileName.text = lastFile + '*'
	else:
		fileName.text = ''


func _on_test_pressed():
	startDemo(selected)


func _on_option_pressed(nextNode):
	if tween.is_active():
		tween.remove(demo.get_node("Dialogue"))
		tween.set_active(false)
		demo.get_node("Dialogue").percent_visible = 1
	else:
		demoIndex = nextNode
		updateDemo()


func _on_speaker_changed(newSpeaker):
	lastSpeaker = newSpeaker


func _on_slot_removed(slot_left, slot_right, nodeName):
	for connection in graph.get_connection_list():
		if (connection['from'] == nodeName and connection['from_port'] == slot_right) or (connection['to'] == nodeName and connection['to_port'] == slot_left):
			graph.disconnect_node(
				connection['from'], connection['from_port'], connection['to'], connection['to_port']
			)
	graph.get_node(nodeName).setSlot(slot_right, slot_right==0)


func _on_SaveDialog_file_selected(path):
	if isTreeComplete():
		lastPath = path
		lastFile = $SaveDialog.current_file
		saveTree(path)
		fileName.text = $SaveDialog.current_file


func _on_LoadDemo_file_selected(path):
	var file = File.new()
	var output
	
	file.open(path, File.READ)
	output = parse_json(file.get_as_text())
	if typeof(output) == TYPE_DICTIONARY:
		demoDict = output
		demoIndex = output[output['Start'][output['Start'].keys()[0]]]['Link']
		updateDemo()
		demo.popup_centered()


func _on_LoadTree_file_selected(path):
	var file = File.new()
	var output
	
	clearGraph()
	commentsLoaded = false
	
	file.open(path, File.READ)
	output = parse_json(file.get_as_text())
	
	if typeof(output) == TYPE_DICTIONARY:
		lastPath = path
		lastFile = $LoadTreeDialog.current_file
		demoDict = output
		fileName.text = $LoadTreeDialog.current_file
		
		$LoadAlertDialog.popup_centered()
		


func _on_LoadAlert_confirmed():
	loadTree('Start')


func _on_PanelToggle_toggled(button_pressed):
	sidePanel.visible = button_pressed

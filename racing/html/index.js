$(function () {
	var races = {};
	var lastRaceSelected = null;
	var currentRaceSelected = '----------';
	var button = document.getElementById('load-start');

	function display(bool) {
		if (bool) {
			$('#racing').show();
			$('#close').show();
		} else {
			$('#racing').hide();
			$('#close').hide();
		}
	}

	display(false);

	window.addEventListener('message', function (event) {
		var item = event.data;
		//Initial called to show NUI
		if (item.type === 'ui') {
			if (item.status == true) {
				display(true);
			} else {
				display(false);
			}
		}
		if (item.type === 'RacesData') {
			//Sending data from server -> client -> NUI
			clearOptions();
			races = item.data;
			races.sort(function (a, b) {
				var a1 = a['name'].toLowerCase(),
					b1 = b['name'].toLowerCase();
				if (a1 == b1) return 0;
				return a1 > b1 ? 1 : -1;
			});
			var option = new Option('----------', '----------');
			$(option).html('');
			$('#races').append(option);
			for (let i = 0; i < races.length; i++) {
				var option = new Option(races[i]['name'] + " | Creator: " + races[i]['creator'], races[i]['_id']);
				$(option).html(races[i]['name']);
				$('#races').append(option);
			}
			$('#races').val(lastRaceSelected);
		}
	});

	$('#load-start').click(function () {
		if (currentRaceSelected == '----------') {
			return;
		}
		lastRaceSelected = currentRaceSelected;
		if (button.textContent == 'Load') {
			$.post('https://racing/loadRace', JSON.stringify({ raceID: lastRaceSelected }));
		} else {
			var laps = parseInt(document.getElementById('voltas').value);
			$.post('https://racing/startRace', JSON.stringify({ voltas: laps }));
			lastRaceSelected = '----------';
		}
		if (currentRaceSelected == lastRaceSelected) {
			button.textContent = 'Start';
		} else {
			button.textContent = 'Load';
		}
	});

	$('#races').change(function () {
		currentRaceSelected = $('#races option:selected').val();
		if (currentRaceSelected == lastRaceSelected) {
			button.textContent = 'Start';
		} else {
			button.textContent = 'Load';
		}
	});

	$('#exit').click(function () {
		$.post('https://racing/exit', JSON.stringify({}));
	});

	function clearOptions() {
		var item = document.getElementById('races');
		item.innerHTML = ''; //<--- Look into a CLEANER option.
	}
});

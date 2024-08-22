$(document).ready(function() {
    var ctx = $('#myChart')[0].getContext('2d');
    var myChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Data Value',
                data: [],
                backgroundColor: 'rgba(255, 99, 132, 0.2)',
                borderColor: 'rgba(255, 99, 132, 1)',
                borderWidth: 1
            }]
        },
        options: {
            scales: {
                y: {
                    beginAtZero: true
                }
            }
        }
    });

    function fetchData() {
        $.ajax({
            url: '/get-data',
            type: 'GET',
            success: function(response) {
                myChart.data.labels = response.map(data => data.time);
                myChart.data.datasets.forEach((dataset) => {
                    dataset.data = response.map(data => data.value);
                });
                myChart.update();
            }
        });
    }

    // Carga inicial
    fetchData();
});

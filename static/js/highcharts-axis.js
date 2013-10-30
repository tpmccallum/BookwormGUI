(function (Highcharts) {
    
    var each = Highcharts.each,
        UNDEFINED;
    
    /**
     * Utility function to remove last occurence of an item from an array
     * @param {Array} arr
     * @param {Mixed} item
     */
    function erase(arr, item) {
        var i = arr.length;
        while (i--) {
            if (arr[i] === item) {
                arr.splice(i, 1);
                break;
            }
        }
        return i;
    }
    /**
     * Add an axis to the chart
     * @param {Object} options The axis option
     * @param {Boolean} isX Whether it is an X axis or a value axis
     */
    Highcharts.Chart.prototype.addAxis = function (options, isX) {
        var chart = this,
            key = isX ? 'xAxis' : 'yAxis',
            axis = new Highcharts.Axis(this, Highcharts.merge(options, {
                index: chart[key].length
            }));

        console.log(key);
        
        // Push the new axis options to the chart options
        chart.options[key] = Highcharts.splat(chart.options[key] || {});
        chart.options[key].push(options);
        console.log(chart, chart.options, chart.options[key]);
    };
    
    /**
     * Remove an axis from the chart
     */
    Highcharts.Axis.prototype.remove = function () {
        if (this.series.length) {
            console.error('Highcharts error: Cannot remove an axis that has connected series');
        } else {
            var chart = this.chart,
                key = this.isXAxis ? 'xAxis' : 'yAxis';

            // clean up chart options
            var axisIndex = this.options.index;
            chart.options[key].splice(axisIndex, 1);
            
            erase(chart.axes, this);
            var index = erase(chart[key], this);
            
            // clean up following axis options (indices)
            for (var i = index; i < chart[key].length; i++) {
              chart[key][i].options.index--;
            }
            
            this.destroy();
            chart.isDirtyBox = true;
            chart.redraw();
        }
    };
    Highcharts.Series.prototype.bindAxes = function () {
        var series = this,
            seriesOptions = series.options,
            chart = series.chart,
            axisOptions;
            
        if (series.isCartesian) {
            
            each(['xAxis', 'yAxis'], function (AXIS) { // repeat for xAxis and yAxis
                
                each(chart[AXIS], function (axis) { // loop through the chart's axis objects
                    
                    axisOptions = axis.options;
                    
                    // apply if the series xAxis or yAxis option mathches the number of the 
                    // axis, or if undefined, use the first axis
                    if ((seriesOptions[AXIS] === axisOptions.index) ||
                            (seriesOptions[AXIS] !== UNDEFINED && seriesOptions[AXIS] === axisOptions.id) || // docs: series.xAxis and series.yAxis can point to axis.id
                            (seriesOptions[AXIS] === UNDEFINED && axisOptions.index === 0)) {
                        
                        // register this series in the axis.series lookup
                        axis.series.push(series);
                        
                        // set this series.xAxis or series.yAxis reference
                        series[AXIS] = axis;
                        
                        // mark dirty for redraw
                        axis.isDirty = true;
                    }
                });

                // The series needs an X and an Y axis
                if (!series[AXIS]) {
                    console.log(AXIS, series);
                    error(17, true);
                }

            });
        }
    };
}(Highcharts));

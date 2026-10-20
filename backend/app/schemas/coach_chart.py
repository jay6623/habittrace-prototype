"""Data-only charts computed by the backend, never executable model output."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

VisualizationFocus = Literal["hour", "weekday", "trend", "comparison", "failure"]


class ChartPoint(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    label: str = Field(min_length=1, max_length=200)
    value: float = Field(ge=0)
    sample_size: int = Field(ge=1)
    completed: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_completed(self) -> "ChartPoint":
        if self.completed is not None and (
            self.completed > self.sample_size
            or self.value != round(self.completed / self.sample_size * 100, 1)
        ):
            raise ValueError("Completed/total counts must agree with the rate")
        return self


class ChartPeriod(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start: date
    end: date


class CoachChartSpec(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    chart_type: Literal["bar", "line"]
    title: str = Field(min_length=1, max_length=200)
    x_axis: str = Field(min_length=1, max_length=100)
    y_axis: str = Field(min_length=1, max_length=100)
    data: list[ChartPoint] = Field(min_length=2, max_length=90)
    units: Literal["percent", "count"]
    period: ChartPeriod
    sample_size: int = Field(ge=5)
    interval_days: Literal[1, 7] | None = None
    focus: VisualizationFocus | None = None
    note: str = Field(min_length=1, max_length=500)

    @model_validator(mode="after")
    def validate_statistics(self) -> "CoachChartSpec":
        if self.period.end < self.period.start:
            raise ValueError("Chart period must be ordered")
        if len({point.label for point in self.data}) != len(self.data):
            raise ValueError("Chart labels must be unique")
        if sum(point.sample_size for point in self.data) != self.sample_size:
            raise ValueError("Chart sample size must match plotted observations")
        if self.units == "percent" and any(point.value > 100 for point in self.data):
            raise ValueError("Completion rates cannot exceed 100 percent")
        if self.focus == "comparison" and (self.chart_type != "bar" or self.interval_days):
            raise ValueError("Period comparisons must be categorical bars")
        if self.focus == "trend" and self.interval_days != 7:
            raise ValueError("Trends must use calendar-week observations")
        return self

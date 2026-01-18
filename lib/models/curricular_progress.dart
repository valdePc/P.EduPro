import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";

interface CurriculumProgressChartProps {
  data: Array<{
    period: string;
    completed: number;
    target: number;
  }>;
}

export default function CurriculumProgressChart({
  data,
}: CurriculumProgressChartProps) {
  return (
    <div className="w-full h-80 bg-white rounded-lg p-4 border border-border">
      <h3 className="font-poppins font-bold text-lg mb-4 text-foreground">
        Avance Curricular por Período
      </h3>
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 20, right: 30, left: 0, bottom: 20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
          <XAxis dataKey="period" />
          <YAxis />
          <Tooltip
            contentStyle={{
              backgroundColor: "#FFFFFF",
              border: "1px solid #E0E0E0",
              borderRadius: "8px",
            }}
          />
          <Legend />
          <Bar dataKey="completed" fill="#0D47A1" name="Completadas" />
          <Bar dataKey="target" fill="#FFA000" name="Meta" />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
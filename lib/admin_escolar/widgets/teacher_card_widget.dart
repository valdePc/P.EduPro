import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { AlertCircle, CheckCircle, AlertTriangle } from "lucide-react";

interface TeacherCardProps {
  name: string;
  level: string;
  grade: string;
  curriculumScore: number;
  attendanceRate: number;
  status: "excellent" | "attention" | "critical";
  onClick?: () => void;
}

export default function TeacherCard({
  name,
  level,
  grade,
  curriculumScore,
  attendanceRate,
  status,
  onClick,
}: TeacherCardProps) {
  const statusConfig = {
    excellent: {
      color: "bg-green-100 border-green-300",
      icon: CheckCircle,
      label: "Excelente",
      textColor: "text-green-700",
    },
    attention: {
      color: "bg-yellow-100 border-yellow-300",
      icon: AlertTriangle,
      label: "Atención",
      textColor: "text-yellow-700",
    },
    critical: {
      color: "bg-red-100 border-red-300",
      icon: AlertCircle,
      label: "Crítico",
      textColor: "text-red-700",
    },
  };

  const config = statusConfig[status];
  const IconComponent = config.icon;

  return (
    <Card
      onClick={onClick}
      className={`p-5 cursor-pointer transition-all hover:shadow-lg border-2 ${config.color}`}
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <h3 className="font-poppins font-bold text-lg text-foreground">
            {name}
          </h3>
          <p className="text-sm text-muted-foreground">
            {level} • {grade}
          </p>
        </div>
        <div className="flex flex-col items-center">
          <IconComponent className={`w-8 h-8 ${config.textColor}`} />
          <Badge className={`mt-2 ${config.textColor} bg-transparent border`}>
            {config.label}
          </Badge>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="bg-white bg-opacity-60 rounded-lg p-3">
          <p className="text-xs text-muted-foreground mb-1">Cumplimiento Curricular</p>
          <div className="flex items-baseline gap-1">
            <span className="text-2xl font-bold text-primary">
              {Math.round(curriculumScore)}%
            </span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-1.5 mt-2">
            <div
              className="bg-primary h-1.5 rounded-full transition-all"
              style={{ width: `${curriculumScore}%` }}
            />
          </div>
        </div>

        <div className="bg-white bg-opacity-60 rounded-lg p-3">
          <p className="text-xs text-muted-foreground mb-1">Asistencia</p>
          <div className="flex items-baseline gap-1">
            <span className="text-2xl font-bold text-green-600">
              {Math.round(attendanceRate)}%
            </span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-1.5 mt-2">
            <div
              className="bg-green-600 h-1.5 rounded-full transition-all"
              style={{ width: `${attendanceRate}%` }}
            />
          </div>
        </div>
      </div>
    </Card>
  );
}
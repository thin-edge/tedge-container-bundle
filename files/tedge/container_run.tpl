{{/*
    golang template to build the docker run options using `docker inspect <container> --format "container_run.tpl"`
    Credit: https://gist.github.com/efrecon/8ce9c75d518b6eb863f667442d7bc679
*/}}
  --name {{printf "%q" .Name}} \
    {{- with .HostConfig}}
        {{- if .Privileged}}
  --privileged \
        {{- end}}
        {{- range $b := .Binds}}
  --volume {{printf "%q" $b}} \
        {{- end}}
        {{- range $v := .VolumesFrom}}
  --volumes-from {{printf "%q" $v}} \
        {{- end}}
        {{- range $l := .Links}}
  --link {{printf "%q" $l}} \
        {{- end}}
        {{- if index . "Mounts"}}
            {{- range $m := .Mounts}}
  --mount type={{.Type}}
                {{- if $s := index $m "Source"}},source={{$s}}{{- end}}
                {{- if $t := index $m "Target"}},destination={{$t}}{{- end}}
                {{- if index $m "ReadOnly"}},readonly{{- end}}
                {{- if $vo := index $m "VolumeOptions"}}
                    {{- range $i, $v := $vo.Labels}}
                        {{- printf ",volume-label=%s=%s" $i $v}}
                    {{- end}}
                    {{- if $dc := index $vo "DriverConfig" }}
                        {{- if $n := index $dc "Name" }}
                            {{- printf ",volume-driver=%s" $n}}
                        {{- end}}
                        {{- range $i, $v := $dc.Options}}
                            {{- printf ",volume-opt=%s=%s" $i $v}}
                        {{- end}}
                    {{- end}}
                {{- end}}
                {{- if $bo := index $m "BindOptions"}}
                    {{- if $p := index $bo "Propagation" }}
                        {{- printf ",bind-propagation=%s" $p}}
                    {{- end}}
                {{- end}} \
            {{- end}}
        {{- end}}
        {{- if .PublishAllPorts}}
  --publish-all \
        {{- end}}
        {{- if .UTSMode}}
  --uts {{printf "%q" .UTSMode}} \
        {{- end}}
  --restart always \
        {{- range $e := .ExtraHosts}}
  --add-host {{printf "%q" $e}} \
        {{- end}}
        {{- range $v := .CapAdd}}
  --cap-add {{printf "%q" $v}} \
        {{- end}}
        {{- range $v := .CapDrop}}
  --cap-drop {{printf "%q" $v}} \
        {{- end}}
        {{- range $d := .Devices}}
  --device {{printf "%q" (index $d).PathOnHost}}:{{printf "%q" (index $d).PathInContainer}}:{{(index $d).CgroupPermissions}} \
        {{- end}}
    {{- end}}
    {{- with .NetworkSettings -}}
        {{- range $p, $conf := .Ports}}
            {{- with $conf}}
  --publish "
                {{- if $h := (index $conf 0).HostIp}}{{$h}}:
                {{- end}}
                {{- (index $conf 0).HostPort}}:{{$p}}" \
            {{- end}}
        {{- end}}
        {{- range $n, $conf := .Networks}}
            {{- with $conf}}
  --network {{printf "%q" $n}} \
            {{- end}}
        {{- end}}
    {{- end}}
    {{- with .Config}}
        {{- if .Domainname}}
  --domainname {{printf "%q" .Domainname}} \
        {{- end}}
        {{- if index . "ExposedPorts"}}
        {{- range $p, $conf := .ExposedPorts}}
  --expose {{printf "%q" $p}} \
        {{- end}}
        {{- end}}
        {{- range $e := .Env}}
  --env {{printf "%q" $e}} \
        {{- end}}
        {{- range $l, $v := .Labels}}
  --label {{printf "%q" $l}}={{printf "%q" $v}} \
        {{- end}}
    {{- if .Tty}}
  --tty \
    {{- end}}
    {{- if .Entrypoint}}
{{- /* Since the entry point cannot be overridden from the command line with an array of size over 1,
       we are fine assuming the default value in such a case. */ -}}
        {{- if eq (len .Entrypoint) 1 }}
  --entrypoint "
            {{- range $i, $v := .Entrypoint}}
                {{- if $i}} {{end}}
                {{- $v}}
            {{- end}}" \
        {{- end}}
    {{- end}}
{{- end}}
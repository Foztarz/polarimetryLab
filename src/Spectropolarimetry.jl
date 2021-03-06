const OFFSET = 100.0 # offset in degrees!!!!
touch(string(getpid(),".pid"))
push!(LOAD_PATH, pwd())
using UnicodePlots, PyCall, Reactive, DataFrames, Light
@pyimport seabreeze
seabreeze.use("pyseabreeze")
@pyimport seabreeze.spectrometers as sb
devices = sb.list_devices()
s = sb.Spectrometer(devices[1])
maxy = s[:_dev][:interface][:_MAX_PIXEL_VALUE]
wl = s[:wavelengths]()
nwl = length(wl)
function watchit()
	watch_file("integrationtime")
	sleep(.1)
	put!(it, parse(Int,readchomp("integrationtime")))
end
function watchnr()
	watch_file("nreplicates")
	sleep(.1)
	take!(nr)
	put!(nr, parse(Int,readchomp("nreplicates")))
end
function watchr()
	watch_file("rotation")
	sleep(.1)
	put!(sp, readchomp("rotation"))
end
it = Channel{Int}(1)
nr = Channel{Int}(1)
put!(nr,1)
sp = Channel{AbstractString}(1)
yy = Input(wl)
X = DataFrame(wl = wl, l315c0 = zeros(nwl), l0c0 = zeros(nwl), l45c0 = zeros(nwl), l90c0 = zeros(nwl), l0c315 = zeros(nwl), l0c45 = zeros(nwl), dark = zeros(nwl), I = zeros(nwl), dolp = zeros(nwl), aop = zeros(nwl), docp = zeros(nwl))
writetable("data.csv", X)

@async map(readall, [`pdflatex plot.tex`, `evince plot.pdf`])

function plotit(y)
	p = scatterplot(wl,y,xlim=[300,800],ylim=[0,maxy])
	display(p)
	sleep(0.07)
end
lift(plotit,yy)
function normalize(I, dolp, aop, docp)
	I = I < 0 ? 0.0 : I > 10maxy ? 10maxy : I
	dolp = dolp < 0 ? 0.0 : dolp > 2 ? 2.0 : dolp
	docp = docp < -2 ? -2.0 : docp > 2 ? 2.0 : docp
	return (I, dolp, aop, docp)
end
function draw()
	if any(map(Bool,X[:l0c315])) && any(map(Bool,X[:l0c45]))
		s0, s1, s2, s3 = measurements2stokes(X[:l315c0] - X[:dark], X[:l0c0] - X[:dark], X[:l45c0] - X[:dark], X[:l90c0] - X[:dark], X[:l0c315] - X[:dark], X[:l0c45] - X[:dark])
	else
		s0, s1, s2, s3 = measurements2stokes(X[:l315c0] - X[:dark], X[:l0c0] - X[:dark], X[:l45c0] - X[:dark], X[:l90c0] - X[:dark])
	end
	for i = 1:nwl
		I, dolp, aop, docp = normalize(stokes2polar(s0[i], s1[i], s2[i], s3[i])...)
		X[i,:I] = I
		X[i,:dolp] = dolp
		X[i,:aop] = rad2deg(aop) + OFFSET
		X[i,:docp] = docp
	end
	writetable("data.csv", X)
	readall(`pdflatex plot.tex`)
end
function iter()
	wait(nr)
	nreps = fetch(nr)
	if isready(it)
		s[:integration_time_micros](take!(it))
	end
	y = zeros(nwl)
	for i = 1:nreps
		y .+= s[:intensities]()
	end
	y /= nreps
	push!(yy,y)
	if isready(sp)
		X[symbol(take!(sp))] = y
		draw()
	end
end
sleep(0)
s[:intensities]()
sleep(0)

@schedule begin 
	while true
		watchit()
	end
end
@schedule begin 
	while true
		watchr()
	end
end
@schedule begin 
	while true
		watchnr()
	end
end
@schedule begin 
	while true
		iter()
	end
end


sleep(60*60*24)


